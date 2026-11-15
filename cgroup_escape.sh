#!/system/bin/sh
# icbc_daily_water / cgroup_escape.sh  —— 把长驻进程挪出「会被冻结的 App cgroup」
#
# Android 12+ 会把退到后台的 App 整个 cgroup 冻住 (cgroup.freeze=1, 进程停在
# do_freezer_trap)。KSU WebUI 里点「开始录制」时, record.sh / getevent / 验证码
# worker 都继承 com.resukisu.resukisu 的 `0::/apps/uid_*/pid_*` cgroup。用户一按
# HOME 切到目标 App, 这几个进程就一起被冻结, 真机表现为:
#   手势一条都录不到、验证码只点到 1~2 个图标就停、确定不点、刷新不点、
#   手动把 WebUI 切回前台(解冻)才继续解开。
# 根 cgroup `0::/` 永远不会被 freezer 冻结; 挪进去后所有子进程自动继承, 且不再
# 随 App 被回收。service.sh 本来就跑在根 cgroup, 由它兜底扫描。
#
# 用法 (都用 sh 调用, 不需要可执行位):
#   sh cgroup_escape.sh [PID ...]   把指定 PID 挪出 App cgroup (不给参数 = 自己)
#   sh cgroup_escape.sh --scan      扫本模块所有进程, 把仍在 App cgroup 的挪出来
# 任何一步失败都静默跳过: 不支持 cgroup v2 / 权限不足的老机型不该因此罢工。

M=/data/adb/modules/icbc_daily_water
ROOT_CG=/sys/fs/cgroup/cgroup.procs
[ -w "$ROOT_CG" ] || exit 0

escape_one() {
  p=$1
  case "$p" in ''|*[!0-9]*) return 0;; esac
  [ -r "/proc/$p/cgroup" ] || return 0
  # 只处理 v2 的 App cgroup; 已经在根 cgroup 的(含 service.sh)什么都不做。
  case "$(sed -n 's/^0:://p' "/proc/$p/cgroup" 2>/dev/null | head -1)" in
    /apps/*) ;;
    *) return 0;;
  esac
  echo "$p" > "$ROOT_CG" 2>/dev/null || return 0
  echo "$(date +%m%d-%H%M%S) CGROUP_ESCAPE pid=$p -> / (app freezer)" >> "$M/log.txt" 2>/dev/null
}

if [ "$1" = "--scan" ]; then
  # pgrep -f 只返回本模块的几个进程, 比遍历几十个冻结 cgroup 的 cgroup.procs 便宜得多。
  for p in $(pgrep -f icbc_daily_water 2>/dev/null); do
    escape_one "$p"
  done
  exit 0
fi

if [ $# -eq 0 ]; then
  set -- $$
fi
for p in "$@"; do
  escape_one "$p"
done
exit 0
