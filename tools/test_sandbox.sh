#!/usr/bin/env bash
# test_sandbox.sh — 需要文件系统沙箱的功能测试
#
# 与 test_regression.sh 的分工:
#   test_regression.sh 是「读源码断言不变量」, 不用沙箱、跑得快, 挡结构性回归;
#   本文件是「真的把脚本跑起来」, 挡行为回归。v0.12.7 之前这类测试住在仓库外面,
#   环境切换时整批丢失且无法从 git 恢复 —— 所以这次一并收进仓库。
#
# 用法: bash tools/test_sandbox.sh
# 退出码: 0 = 全绿, 1 = 有断言失败

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

# 沙箱根。优先用环境偏好的临时目录, 不用 /tmp —— Termux 下 /tmp 往往不可写。
BASE="${TMPDIR:-/data/data/com.termux/files/usr/tmp}"
[ -d "$BASE" ] || mkdir -p "$BASE"
SB=$(mktemp -d "$BASE/wc_sandbox.XXXXXX") || { echo "无法创建沙箱"; exit 1; }
trap 'rm -rf "$SB"' EXIT

FAILS=0
ok()   { printf '  ok   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAILS=$((FAILS+1)); }
sec()  { printf '\n[%s]\n' "$*"; }

# ---------- 铺沙箱 ----------
# webctl.sh 里只有两处绝对路径前缀需要改写:
#   /data/adb/modules/icbc_daily_water  -> $SB/modules/icbc_daily_water
#   /data/adb/icbc_water                -> $SB/icbc_water
# 只改前缀不改结构, 保证被测代码本身一字未动。
M="$SB/modules/icbc_daily_water"
W="$SB/icbc_water"
mkdir -p "$M" "$W/profiles/icbc" "$W/profiles/inheritme"

cp webctl.sh "$M/webctl.sh"
sed -i \
  -e "s#/data/adb/modules/icbc_daily_water#$M#g" \
  -e "s#/data/adb/icbc_water#$W#g" \
  "$M/webctl.sh"

# 配置基线: 与仓库里的 sched.conf 同源, 但只保留本次要用的键
{
  echo "SCHED_ENABLE=1"
  echo "SCHED_TIME=0730"
} > "$W/sched.conf"

# 内置工行 profile: 关键在于它「天生就带 P_SCHED」(安装时从 SCHED_TIME 快照来的)
# —— 这正是 settime 原本失效的原因。
{
  echo "P_NAME=工行定时浇水"
  echo "P_TYPE=script"
  echo "P_PKG=com.icbc"
  echo "P_SCHED=0730"
} > "$W/profiles/icbc/conf"

# 另一个 profile: 刻意不写 P_SCHED, 用来验证「没写的仍然继承全局」这条回落没被破坏
{
  echo "P_NAME=继承型"
  echo "P_TYPE=record"
  echo "P_PKG=com.example.app"
} > "$W/profiles/inheritme/conf"

CTL="sh $M/webctl.sh"

gk() {  # gk FILE KEY -> VALUE
  sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1
}


# ============ 1. settime 必须同时写两处 ============
sec "1. settime 同步写 sched.conf 与内置工行 profile"

OUT=$($CTL settime 0815 2>&1); RC=$?
if [ "$RC" != "0" ]; then
  fail "settime 0815 退出码 $RC: $OUT"
else
  ok "退出码 0"
fi

ST=$(gk "$W/sched.conf" SCHED_TIME)
PS=$(gk "$W/profiles/icbc/conf" P_SCHED)
[ "$ST" = "0815" ] && ok "sched.conf 的 SCHED_TIME -> $ST" \
                   || fail "sched.conf 的 SCHED_TIME 是 '$ST', 应为 0815"
[ "$PS" = "0815" ] && ok "profiles/icbc/conf 的 P_SCHED -> $PS" \
                   || fail "P_SCHED 是 '$PS', 应为 0815 —— 调度器只读这个, 工行仍按旧时间跑"

# 输出要让命令行用户看得见到底改了什么
case "$OUT" in
  *"SET SCHED_TIME=0815"*) ok "回显 SET SCHED_TIME=0815" ;;
  *) fail "回显里没有 SET SCHED_TIME=0815: $OUT" ;;
esac
case "$OUT" in
  *"SET P_SCHED=0815"*) ok "回显 SET P_SCHED=0815" ;;
  *) fail "回显里没有 SET P_SCHED=0815: $OUT" ;;
esac


# ============ 2. 回落不能被破坏 ============
sec "2. 没有自己 P_SCHED 的 profile 仍然继承全局"

# 上面那个 profile 故意没写 P_SCHED, settime 不该去给它凭空造一个 ——
# 造了就等于把它从「跟随全局」变成「钉死在当前值」, 以后再改全局它就不动了。
if grep -q '^P_SCHED=' "$W/profiles/inheritme/conf" 2>/dev/null; then
  fail "给没有 P_SCHED 的 profile 凭空写入了 P_SCHED —— 回落被破坏"
else
  ok "继承型 profile 未被写入 P_SCHED, 回落路径完好"
fi


# ============ 3. 输入校验不能松 ============
sec "3. settime 的取值校验"

for bad in "9999" "073" "07300" "abcd" "" "2460" "0760"; do
  OUT=$($CTL settime "$bad" 2>&1); RC=$?
  if [ "$RC" = "0" ]; then
    fail "settime '$bad' 竟然被接受(退出码 0)"
  else
    ok "settime '$bad' 被拒绝"
  fi
done
# 校验失败不该动配置
ST=$(gk "$W/sched.conf" SCHED_TIME)
[ "$ST" = "0815" ] && ok "非法输入后 SCHED_TIME 仍是 $ST" \
                   || fail "非法输入把 SCHED_TIME 改成了 '$ST'"


# ============ 4. profile set 走的还是另一条路 ============
sec "4. WebUI 用的 profile set p_sched 仍然独立工作"

OUT=$($CTL profile set icbc p_sched 0945 2>&1); RC=$?
PS=$(gk "$W/profiles/icbc/conf" P_SCHED)
[ "$RC" = "0" ] && [ "$PS" = "0945" ] && ok "profile set icbc p_sched 0945 -> P_SCHED=$PS" \
               || fail "profile set p_sched 失败 rc=$RC P_SCHED='$PS' out=$OUT"

# 两条路都能写 P_SCHED, 各自独立 —— 再用 settime 改回去, 应该覆盖掉上面的 0945
OUT=$($CTL settime 1010 2>&1)
PS=$(gk "$W/profiles/icbc/conf" P_SCHED)
[ "$PS" = "1010" ] && ok "settime 覆盖掉 profile set 的值 -> P_SCHED=$PS" \
                   || fail "settime 没能覆盖, P_SCHED='$PS'"


# ============ 5. PIN 不得回显 ============
sec "5. 明文 PIN 不出现在任何输出里"

OUT=$(WEBUI_PIN=2468 $CTL setpin 2>&1)
case "$OUT" in
  *2468*) fail "setpin 的输出里出现了明文 PIN" ;;
  *) ok "setpin 输出不含明文" ;;
esac


# ============ 6. device set: 标签往返 / 总闸清理 / 检测时序 ============
# 这一节之前完全不存在 —— 六条守卫全绿却漏掉了「保存按钮没反应」那个主故障,
# 因为 webctl.sh 的 device 段一条断言都没有。
sec "6. device set 的标签往返、总闸清理与检测时序"

DEVF="$W/device.conf"

# 6.1 一次完整的「换机」写入, 数值就是用户手工填的 1440x3200
OUT=$($CTL device set DEV_APPLY=1 DEV_MODEL=M2102K1C DEV_LABEL=Xiaomi_11 \
      DEV_STATUS=testing DEV_SW=1440 DEV_SH=3200 DEV_D=0 DEV_DPI=560 \
      DEV_PIN_X0=290 DEV_PIN_Y0=1015 DEV_PIN_DX=320 DEV_PIN_DY=210 \
      DEV_PAT_X0=300 DEV_PAT_Y0=1050 DEV_PAT_DX=360 DEV_PAT_DY=360 2>&1); RC=$?
[ "$RC" = "0" ] && ok "device set 16 键 rc=0" || fail "device set 失败 rc=$RC: $OUT"

DEV_OK=1
for kv in DEV_APPLY=1 DEV_MODEL=M2102K1C DEV_LABEL=Xiaomi_11 DEV_STATUS=testing \
          DEV_SW=1440 DEV_SH=3200 DEV_D=0 DEV_DPI=560 \
          DEV_PIN_X0=290 DEV_PIN_Y0=1015 DEV_PIN_DX=320 DEV_PIN_DY=210 \
          DEV_PAT_X0=300 DEV_PAT_Y0=1050 DEV_PAT_DX=360 DEV_PAT_DY=360
do
  K=${kv%%=*}; V=${kv#*=}
  GV=$(gk "$DEVF" "$K")
  [ "$GV" = "$V" ] || { fail "$K='$GV' 应为 '$V'"; DEV_OK=0; }
done
[ "$DEV_OK" = "1" ] && ok "16 个键全部按存储形态落盘 (含图案宫格 DEV_PAT_*)"

# 6.1b 图案坐标必须过「纯数字」闸, 否则服务端拖拽会拿到非数字坐标
OUT=$($CTL device set DEV_PAT_X0=abc 2>&1); RC=$?
[ "$RC" != "0" ] && ok "DEV_PAT_X0=abc 被拒绝 (rc=$RC)" \
                 || fail "DEV_PAT_X0=abc 竟然被接受了"
GV=$(gk "$DEVF" DEV_PAT_X0)
[ "$GV" = "300" ] && ok "拒绝后 DEV_PAT_X0 仍是 300" \
                  || fail "拒绝后 DEV_PAT_X0 变成 '$GV' —— 非法输入动了配置"

# 6.2 device get 回显存储形态(下划线), 界面读到后再转成空格显示
OUT=$($CTL device get 2>&1)
case "$OUT" in
  *DEV_LABEL=Xiaomi_11*) ok "device get 回显 DEV_LABEL=Xiaomi_11" ;;
  *) fail "device get 没回显 DEV_LABEL=Xiaomi_11: $OUT" ;;
esac
case "$OUT" in
  *"DEV_APPLIED=1"*) ok "DEV_APPLIED=1" ;;
  *) fail "DEV_APPLIED 不为 1: $OUT" ;;
esac

# 6.3 带空格的显示名必须被拒, 且一个字节都不能写。
#     这正是 v0.12.9「保存按钮没反应」的镜像: 界面现在先转下划线, 后端仍是最后一道闸。
OUT=$($CTL device set DEV_LABEL='Xiaomi 11' 2>&1); RC=$?
[ "$RC" != "0" ] && ok "带空格的 DEV_LABEL 被拒绝 (rc=$RC)" \
                 || fail "带空格的 DEV_LABEL 竟然被接受了"
GV=$(gk "$DEVF" DEV_LABEL)
[ "$GV" = "Xiaomi_11" ] && ok "拒绝后 DEV_LABEL 仍是 Xiaomi_11" \
                        || fail "拒绝后 DEV_LABEL 变成 '$GV' —— 非法输入动了配置"

# 6.4 关总闸: 数值键必须被真的删掉, 手填的显示名必须保留
OUT=$($CTL device set DEV_APPLY=0 2>&1); RC=$?
[ "$RC" = "0" ] && ok "device set DEV_APPLY=0 rc=0" || fail "关总闸失败: $OUT"
GONE=1
for K in DEV_SW DEV_SH DEV_D DEV_DPI DEV_PIN_X0 DEV_PIN_Y0 DEV_PIN_DX DEV_PIN_DY \
         DEV_PAT_X0 DEV_PAT_Y0 DEV_PAT_DX DEV_PAT_DY; do
  GV=$(gk "$DEVF" "$K")
  [ -n "$GV" ] && { fail "关总闸后 $K 仍残留 '$GV' —— 注释承诺清掉却没清"; GONE=0; }
done
[ "$GONE" = "1" ] && ok "12 个数值键全部删掉, 不再残留上一台机器的分辨率/图案坐标"
GV=$(gk "$DEVF" DEV_LABEL)
[ "$GV" = "Xiaomi_11" ] && ok "手填的 DEV_LABEL=Xiaomi_11 被保留" \
                        || fail "关总闸把显示名改成了 '$GV' —— 用户输入被覆盖"
[ "$(gk "$DEVF" DEV_MODEL)" = "17pro" ] && ok "DEV_MODEL 回落 17pro" \
                                       || fail "DEV_MODEL=$(gk "$DEVF" DEV_MODEL), 应为 17pro"

# 6.5 再开总闸: 数值不会凭空回来(由界面回落到 17 Pro 的 1220x2656)
$CTL device set DEV_APPLY=1 >/dev/null 2>&1
GV=$(gk "$DEVF" DEV_SW)
[ -z "$GV" ] && ok "重开总闸后 DEV_SW 仍为空, 由界面回落 1220" \
              || fail "重开总闸后 DEV_SW 凭空回来: '$GV'"

# 6.6 检测时序: DEV_DETECT 必须排在最后, 而且没拿到东西时必须报 none。
#     旧版在任何检测动作之前就无条件 echo DEV_DETECT=ok, wm/getprop 拿不到值时
#     界面照样提示「已检测到本机参数」, 用户据此去保存就会踩空。
OUT=$($CTL device detect 2>&1)
ND=$(printf '%s\n' "$OUT" | grep -cE '^DEV_DETECT=' || true)
[ "$ND" = "1" ] && ok "输出里恰好 1 行 DEV_DETECT" \
               || fail "DEV_DETECT 出现 $ND 行, 界面只认第一处"
HASNUM=0
printf '%s\n' "$OUT" | grep -qE '^DEV_(SW|SH|DPI)=' && HASNUM=1
if [ "$HASNUM" = "1" ]; then
  printf '%s\n' "$OUT" | grep -q '^DEV_DETECT=ok$' \
    && ok "拿到数值 -> 报 DEV_DETECT=ok" \
    || fail "拿到数值却没报 ok: $OUT"
else
  printf '%s\n' "$OUT" | grep -q '^DEV_DETECT=ok$' \
    && fail "一个数值都没拿到却报了 ok —— 界面会提示「已检测到本机参数」" \
    || ok "没拿到数值 -> 报 none, 不再谎报 ok"
fi
LASTLINE=$(printf '%s\n' "$OUT" | tail -1)
case "$LASTLINE" in
  DEV_DETECT=*) ok "DEV_DETECT 是输出最后一行 (先给结果, 末尾才汇报)" ;;
  *) fail "DEV_DETECT 不是最后一行, 当前末行='$LASTLINE'" ;;
esac
case "$OUT" in
  *DEV_PIN_HINT=manual*) ok "DEV_PIN_HINT=manual 仍在, 宫格提示没丢" ;;
  *) fail "DEV_PIN_HINT=manual 丢了: $OUT" ;;
esac


# ============ 7. 执行日: 全局 setdays 与单任务 p_days ============
sec "7. 执行日 setdays / p_days 的取值校验"

# 7.1 合法值逐个落盘
for good in "" "0" "135" "1234567"; do
  OUT=$($CTL setdays "$good" 2>&1); RC=$?
  GV=$(gk "$W/sched.conf" SCHED_DAYS)
  if [ "$RC" = "0" ] && [ "$GV" = "$good" ]; then
    ok "setdays '$good' -> SCHED_DAYS='$GV'"
  else
    fail "setdays '$good' rc=$RC SCHED_DAYS='$GV' out=$OUT"
  fi
done

# 7.2 非法值必须被拒, 且一个字节都不写
$CTL setdays 135 >/dev/null 2>&1
for bad in "132" "8" "11" "01" "abc" "12345678" "765"; do
  OUT=$($CTL setdays "$bad" 2>&1); RC=$?
  GV=$(gk "$W/sched.conf" SCHED_DAYS)
  if [ "$RC" = "0" ]; then
    fail "setdays '$bad' 竟然被接受(退出码 0)"
  elif [ "$GV" != "135" ]; then
    fail "setdays '$bad' 被拒了, 但 SCHED_DAYS 被改成了 '$GV'"
  else
    ok "setdays '$bad' 被拒, SCHED_DAYS 仍是 135"
  fi
done

# 7.3 单任务执行日: 空=跟随全局, 0=不跑, 升序串=指定几天
OUT=$($CTL profile set inheritme p_days 246 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_DAYS)
[ "$RC" = "0" ] && [ "$GV" = "246" ] && ok "profile set p_days 246 -> P_DAYS=$GV" \
               || fail "profile set p_days 246 失败 rc=$RC P_DAYS='$GV' out=$OUT"
OUT=$($CTL profile set inheritme p_days 0 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_DAYS)
[ "$RC" = "0" ] && [ "$GV" = "0" ] && ok "p_days 0 (一周都不跑) 被接受" \
               || fail "p_days 0 失败 rc=$RC P_DAYS='$GV' out=$OUT"
for bad in "132" "8" "9" "007"; do
  OUT=$($CTL profile set inheritme p_days "$bad" 2>&1); RC=$?
  GV=$(gk "$W/profiles/inheritme/conf" P_DAYS)
  if [ "$RC" = "0" ]; then
    fail "profile set p_days '$bad' 竟然被接受"
  elif [ "$GV" != "0" ]; then
    fail "p_days '$bad' 被拒了, 但 P_DAYS 被改成了 '$GV'"
  else
    ok "profile set p_days '$bad' 被拒, P_DAYS 仍是 0"
  fi
done
# 清空 = 回到「跟随全局」
OUT=$($CTL profile set inheritme p_days "" 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_DAYS)
[ "$RC" = "0" ] && [ -z "$GV" ] && ok "p_days 置空 -> 跟随全局" \
               || fail "p_days 置空失败 rc=$RC P_DAYS='$GV' out=$OUT"


# ============ 8. 内置工行任务: 删得掉, 也不会被悄悄重建 ============
sec "8. 内置工行任务的删除与恢复"

[ -f "$W/profiles/icbc/conf" ] && ok "测试前置: 内置工行 profile 存在" \
                              || fail "测试前置: 内置工行 profile 不在, 后面的断言无意义"

OUT=$($CTL profile del icbc 2>&1); RC=$?
[ "$RC" = "0" ] && ok "profile del icbc rc=0 ($OUT)" \
               || fail "profile del icbc 失败 rc=$RC: $OUT"
[ ! -d "$W/profiles/icbc" ] && ok "profiles/icbc 目录已被删除" \
                            || fail "profiles/icbc 目录还在"
# 关键: 不立 no_icbc 标记的话, service.sh 每次开机 / customize.sh 每次安装都会把它建回来
[ -f "$W/no_icbc" ] && ok "no_icbc 标记已写入 —— 开机/升级不会再重建" \
                    || fail "no_icbc 标记没写, 开机会把内置任务重建回来"
# 别的任务不能被误伤
[ -f "$W/profiles/inheritme/conf" ] && ok "删除内置任务没有误伤其它 profile" \
                                    || fail "inheritme 也被删了"

# 恢复: 撤标记 + 重建 + 带上当前全局时间
OUT=$($CTL profile addicbc 2>&1); RC=$?
[ "$RC" = "0" ] && ok "profile addicbc rc=0 ($OUT)" \
               || fail "profile addicbc 失败 rc=$RC: $OUT"
[ -f "$W/profiles/icbc/conf" ] && ok "profiles/icbc 已重建" \
                              || fail "profiles/icbc 没重建"
[ ! -f "$W/no_icbc" ] && ok "no_icbc 标记已撤销 —— 恢复不是只成功一次的假动作" \
                      || fail "no_icbc 标记还在, 下次开机又会被跳过"
GV=$(gk "$W/profiles/icbc/conf" P_SCHED)
ST=$(gk "$W/sched.conf" SCHED_TIME)
[ "$GV" = "$ST" ] && [ -n "$GV" ] && ok "重建的 P_SCHED=$GV 取自当前 SCHED_TIME=$ST" \
                || fail "重建的 P_SCHED='$GV', 应等于 SCHED_TIME='$ST'"
GV=$(gk "$W/profiles/icbc/conf" P_TYPE)
[ "$GV" = "script" ] && ok "重建后仍是 script 型 (走 water.sh)" \
                    || fail "重建后 P_TYPE='$GV', 应为 script"
# 已存在时不该重复建
OUT=$($CTL profile addicbc 2>&1); RC=$?
[ "$RC" != "0" ] && ok "已存在时 addicbc 被拒绝" \
                 || fail "内置任务已存在, addicbc 竟然又建了一次"


# ============ 9. 录制方式: 全场录取与指定包名录取互相牵制 ============
sec "9. p_scope=all 与 p_pkg 的双向牵制"

OUT=$($CTL profile set inheritme p_scope all 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_SCOPE)
GP=$(gk "$W/profiles/inheritme/conf" P_PKG)
[ "$RC" = "0" ] && [ "$GV" = "all" ] && ok "p_scope all -> P_SCOPE=$GV" \
               || fail "p_scope all 失败 rc=$RC P_SCOPE='$GV' out=$OUT"
[ -z "$GP" ] && ok "P_PKG 已被清空 —— 否则回放先去打开包名, 全场录的动作全错位" \
             || fail "P_SCOPE=all 但 P_PKG 仍是 '$GP'"
case "$OUT" in
  *"SET P_PKG="*) ok "回显里带了 SET P_PKG=" ;;
  *) fail "回显里没有 SET P_PKG=: $OUT" ;;
esac

# 反向: 给了非空包名必须退回 pkg 模式, 不能停在自相矛盾的 all+包名
OUT=$($CTL profile set inheritme p_pkg com.example.other 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_SCOPE)
GP=$(gk "$W/profiles/inheritme/conf" P_PKG)
[ "$RC" = "0" ] && [ "$GP" = "com.example.other" ] && ok "p_pkg 落盘 -> P_PKG=$GP" \
               || fail "p_pkg 失败 rc=$RC P_PKG='$GP' out=$OUT"
[ "$GV" = "pkg" ] && ok "P_SCOPE 自动退回 pkg —— 指定包名录取这条核心路径没被破坏" \
                  || fail "给了包名后 P_SCOPE 仍是 '$GV', 应为 pkg"

OUT=$($CTL profile set inheritme p_scope nowhere 2>&1); RC=$?
GV=$(gk "$W/profiles/inheritme/conf" P_SCOPE)
[ "$RC" != "0" ] && [ "$GV" = "pkg" ] && ok "非法 scope 被拒且配置未动" \
                 || fail "非法 scope rc=$RC P_SCOPE='$GV'"

# 新建时就能选全场录取, 且从头就不带包名
OUT=$($CTL profile add allrec 全场任务 "" 0900 all 2>&1); RC=$?
[ "$RC" = "0" ] && ok "profile add ... all rc=0 ($OUT)" \
               || fail "profile add scope=all 失败 rc=$RC: $OUT"
GV=$(gk "$W/profiles/allrec/conf" P_SCOPE)
GP=$(gk "$W/profiles/allrec/conf" P_PKG)
[ "$GV" = "all" ] && [ -z "$GP" ] && ok "新建即 P_SCOPE=all 且 P_PKG 为空" \
                 || fail "新建任务 P_SCOPE='$GV' P_PKG='$GP'"


# ============ 10. 图案解锁: 脱敏回显 + 取值校验 ============
sec "10. setpattern 的脱敏与取值校验"

OUT=$(WEBUI_PATTERN=14789 $CTL setpattern 2>&1); RC=$?
GV=$(gk "$W/sched.conf" PATTERN)
[ "$RC" = "0" ] && [ "$GV" = "14789" ] && ok "图案已写入配置" \
               || fail "setpattern rc=$RC PATTERN='$GV' out=$OUT"
case "$OUT" in
  *14789*) fail "setpattern 的输出里出现了明文点序" ;;
  *) ok "setpattern 输出不含明文点序" ;;
esac
case "$OUT" in
  *"SET PATTERN=已设置"*) ok "回显 SET PATTERN=已设置" ;;
  *) fail "回显不是「已设置」: $OUT" ;;
esac
# status 是 WebUI 轮询的接口, 同样不能把点序带出去
OUT=$($CTL status 2>&1)
case "$OUT" in
  *14789*) fail "status 的输出里出现了明文点序" ;;
  *) ok "status 输出不含明文点序" ;;
esac

# 非法点序逐个拒绝: 重复 / 含 0 / 太短 / 太长
for bad in "1111" "0123" "123" "1234567890" "12a4"; do
  OUT=$(WEBUI_PATTERN="$bad" $CTL setpattern 2>&1); RC=$?
  GV=$(gk "$W/sched.conf" PATTERN)
  if [ "$RC" = "0" ]; then
    fail "图案 '$bad' 竟然被接受"
  elif [ "$GV" != "14789" ]; then
    fail "图案 '$bad' 被拒了, 但 PATTERN 被改成了 '$GV'"
  else
    ok "图案 '$bad' 被拒, 已保存的图案未被覆盖"
  fi
done

# 清空 = 回到 PIN / 上滑
OUT=$(WEBUI_PATTERN= $CTL setpattern 2>&1); RC=$?
GV=$(gk "$W/sched.conf" PATTERN)
[ "$RC" = "0" ] && [ -z "$GV" ] && ok "空图案清除成功 (回到 PIN/上滑)" \
               || fail "清除图案失败 rc=$RC PATTERN='$GV' out=$OUT"

# 解锁方式三选一
OUT=$($CTL setmode pattern 2>&1); RC=$?
GV=$(gk "$W/sched.conf" UNLOCK_MODE)
[ "$RC" = "0" ] && [ "$GV" = "pattern" ] && ok "setmode pattern -> UNLOCK_MODE=$GV" \
               || fail "setmode pattern 失败 rc=$RC UNLOCK_MODE='$GV' out=$OUT"
OUT=$($CTL setmode banana 2>&1); RC=$?
[ "$RC" != "0" ] && ok "setmode banana 被拒" || fail "setmode banana 竟然被接受"
GV=$(gk "$W/sched.conf" UNLOCK_MODE)
[ "$GV" = "pattern" ] && ok "拒绝后 UNLOCK_MODE 仍是 pattern" \
                      || fail "拒绝后 UNLOCK_MODE 变成 '$GV'"


# ============ 11. unlock 往返测试不能挂死 ============
sec "11. unlock 子命令在服务不在时立刻报错"

# 沙箱里没有 service.sh 在跑, unlock 必须马上 ERR 而不是干等 30 秒;
# 30 秒轮询是留给「服务活着但结果没回来」的场景的。
T0=$(date +%s)
OUT=$($CTL unlock 2>&1); RC=$?
T1=$(date +%s)
[ "$RC" != "0" ] && ok "服务不在时 unlock 返回非 0 (rc=$RC)" \
                 || fail "服务不在时 unlock 竟然报成功"
case "$OUT" in
  ERR*) ok "回显是 ERR: $OUT" ;;
  *) fail "回显不是 ERR: $OUT" ;;
esac
if [ $((T1 - T0)) -lt 20 ]; then
  ok "没有干等到超时, 用时 $((T1 - T0))s"
else
  fail "unlock 用了 $((T1 - T0))s —— 服务不在时应立刻退出"
fi


# ============ 汇总 ============
printf '\n'
if [ "$FAILS" = "0" ]; then
  echo "沙箱功能测试: 全部通过"
  exit 0
fi
echo "沙箱功能测试: $FAILS 条失败"
exit 1
