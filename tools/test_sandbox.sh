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
      DEV_PIN_X0=290 DEV_PIN_Y0=1015 DEV_PIN_DX=320 DEV_PIN_DY=210 2>&1); RC=$?
[ "$RC" = "0" ] && ok "device set 12 键 rc=0" || fail "device set 失败 rc=$RC: $OUT"

DEV_OK=1
for kv in DEV_APPLY=1 DEV_MODEL=M2102K1C DEV_LABEL=Xiaomi_11 DEV_STATUS=testing \
          DEV_SW=1440 DEV_SH=3200 DEV_D=0 DEV_DPI=560 \
          DEV_PIN_X0=290 DEV_PIN_Y0=1015 DEV_PIN_DX=320 DEV_PIN_DY=210
do
  K=${kv%%=*}; V=${kv#*=}
  GV=$(gk "$DEVF" "$K")
  [ "$GV" = "$V" ] || { fail "$K='$GV' 应为 '$V'"; DEV_OK=0; }
done
[ "$DEV_OK" = "1" ] && ok "12 个键全部按存储形态落盘"

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
for K in DEV_SW DEV_SH DEV_D DEV_DPI DEV_PIN_X0 DEV_PIN_Y0 DEV_PIN_DX DEV_PIN_DY; do
  GV=$(gk "$DEVF" "$K")
  [ -n "$GV" ] && { fail "关总闸后 $K 仍残留 '$GV' —— 注释承诺清掉却没清"; GONE=0; }
done
[ "$GONE" = "1" ] && ok "8 个数值键全部删掉, 不再残留上一台机器的分辨率"
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


# ============ 汇总 ============
printf '\n'
if [ "$FAILS" = "0" ]; then
  echo "沙箱功能测试: 全部通过"
  exit 0
fi
echo "沙箱功能测试: $FAILS 条失败"
exit 1
