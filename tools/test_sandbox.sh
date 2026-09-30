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


# ============ 汇总 ============
printf '\n'
if [ "$FAILS" = "0" ]; then
  echo "沙箱功能测试: 全部通过"
  exit 0
fi
echo "沙箱功能测试: $FAILS 条失败"
exit 1
