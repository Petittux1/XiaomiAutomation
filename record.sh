#!/system/bin/sh
# PATH: 本脚本经常被桥 (WebUI / ksud / Magisk 模块) 以 root 拉起, 那时的 PATH 由
# 宿主决定, 有的宿主不含 /system/bin —— 缺了它 setsid/getevent/dumpsys 全都找不到,
# 表现就是「点开始录制没有任何反应」。先把标准路径补在最前面, 再交给业务逻辑。
PATH=/system/bin:/system/xbin:/sbin:/vendor/bin:$PATH
export PATH
# icbc_daily_water / record.sh v0.9.6  操作录制内核
# 纯 root 后台录制: getevent 读触摸事件流 -> 压缩成动作序列 actions.rx
# 用法: record.sh start PROFILE | stop PROFILE | status
# 行为: 从 WebUI 点「开始」起, 等「目标 app 打开到前台」才真正开录(切换动作不录);
#       之后**只在目标 app 停留期间**录取: 切走/回桌面自动暂停, 回到目标 app 继续,
#       锁屏/暗屏自动暂停, 解锁继续; 「停止」收尾存档。
#       P_PKG 为空 = 亮屏即开录全量录入 (适合先测坐标/无固定 app 的操作)。
#       录制方式见 profile conf 的 P_SCOPE:
#         空/pkg = 指定包名录取 (上面那条绑定规则, 核心路径)
#         all    = 全场录取     (不绑定包名, 不因切 app 暂停, 系统手势区也照录)
#       PROFILE 为 profiles/ 下目录名(ASCII slug), 显示名在 conf P_NAME。
M=/data/adb/modules/icbc_daily_water
BASE=/data/adb/icbc_water
PFX=$BASE/profiles
PIDF=$BASE/rec.pid
TMP=$BASE/rec.tmp.actions
NAME=$BASE/rec.name   # 当前正在录制的 profile 名 (daemon 写, stop 删, status 读)
LOG=$BASE/rec.log

log() { echo "$(date +%m%d-%H%M%S) $*" >> $LOG; }

# 录制 profile 目录名白名单；避免 stop/pkill 把 shell 元字符当参数模式。
slugok() {
  [ -n "$1" ] || return 1
  case "$1" in
    *' '*|*'/'*|*'\\'*|*"'"*|*'"'*|*'`'*) return 1;;
    *'$'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*) return 1;;
    *'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'#'*|*'='*|*'.'*) return 1;;
  esac
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}

restore_rec_stayon() {
  RS=$(cat $BASE/rec.stayon 2>/dev/null)
  case "$RS" in
    true|false|usb|ac|wireless) svc power stayon "$RS" 2>/dev/null;;
  esac
  rm -f $BASE/rec.stayon 2>/dev/null
}

# 回放期间禁止新录制；回放进程异常退出后由 owner PID 自动清理陈旧锁。
replay_busy() {
  [ -d "$BASE/replay.lock" ] || return 1
  RP=$(cat "$BASE/replay.lock/owner" 2>/dev/null)
  case "$RP" in
    ''|*[!0-9]*) rm -rf "$BASE/replay.lock" 2>/dev/null; return 1;;
  esac
  if kill -0 "$RP" 2>/dev/null; then return 0; fi
  rm -rf "$BASE/replay.lock" 2>/dev/null
  return 1
}

START_LOCK=$BASE/rec.start.lock
release_start_lock() { rm -rf "$START_LOCK" 2>/dev/null; }
acquire_start_lock() {
  if mkdir "$START_LOCK" 2>/dev/null; then
    echo $$ > "$START_LOCK/owner" 2>/dev/null
    return 0
  fi
  LP=$(cat "$START_LOCK/owner" 2>/dev/null)
  case "$LP" in
    ''|*[!0-9]*) rm -rf "$START_LOCK" 2>/dev/null;;
    *) kill -0 "$LP" 2>/dev/null && return 1;;
  esac
  rm -rf "$START_LOCK" 2>/dev/null
  mkdir "$START_LOCK" 2>/dev/null || return 1
  echo $$ > "$START_LOCK/owner" 2>/dev/null
  return 0
}

# ---- TDEV_DISC_BEGIN 触摸设备发现 (四份拷贝必须逐字一致, 回归第 11 节比对) ----
# 不能只认设备名: 换个机型触摸控制器的名字就变 (Xiaomi_Touch_Input_0/_1、
# xiaomi_touch、fts、goodix、synaptics ...), 以前写死 Xiaomi_Touch_Input_0, 找不到
# 就回落到写死的 event8 —— 那个节点在别的机器上可能是指纹/耳机 jack:
#   · 解锁: event8 是另一个触摸节点时轴 max 不同, K = 轴max/SW 就算错, 图案整片
#     画偏 (真机反馈: Xiaomi 15 Pro 用户「图案解锁搁那瞎划拉」); 轴 max <= 20000 时
#     K 干脆停在 100, 偏得更远。
#   · 录制: 同一处判据, event8 不存在 -> daemon 秒退 -> 界面只剩「ERR start failed」。
# 判据改成能力: 必须同时有 ABS_MT 的 X(0035)/Y(0036) 两轴, 分数高者胜出 ——
# 轴范围越大越可能是主屏触摸 (17 Pro 的 _0 是 121999x265599, _1 只有 90399x57199),
# 名字只当加分项。一个都判不出来才回落 event8, 并把 TDEV_HOW=fallback 留给调用方记日志。
touch_score() {  # $1 = /dev/input/eventN; 0 = 不是触摸屏, 否则分数
  TS_P=$(getevent -p "$1" 2>/dev/null)
  [ -n "$TS_P" ] || { echo 0; return; }
  TS_X=; TS_Y=
  case "$TS_P" in *0035[[:space:]]*:*) TS_X=1;; esac
  case "$TS_P" in *ABS_MT_POSITION_X*) TS_X=1;; esac
  case "$TS_P" in *0036[[:space:]]*:*) TS_Y=1;; esac
  case "$TS_P" in *ABS_MT_POSITION_Y*) TS_Y=1;; esac
  [ -n "$TS_X" ] && [ -n "$TS_Y" ] || { echo 0; return; }
  # 只从 0035: 的轴明细行取 max, 不能命中只列代码的摘要行。
  TS_M=$(printf '%s\n' "$TS_P" | grep -A2 -m1 -E '(^|[[:space:]])0035[[:space:]]*:|ABS_MT_POSITION_X' | grep -m1 'max' | sed -E 's/.*max[^0-9]*([0-9]+).*/\1/')
  case "$TS_M" in ''|*[!0-9]*) TS_M=0;; esac
  TS_S=2
  [ "$TS_M" -gt 20000 ] && TS_S=$((TS_S+2))
  [ "$TS_M" -gt 80000 ] && TS_S=$((TS_S+2))
  case "$TS_P" in *Xiaomi_Touch_Input_0*) TS_S=$((TS_S+4));; esac
  case "$TS_P" in *[Tt][Oo][Uu][Cc][Hh]*) TS_S=$((TS_S+1));; esac
  echo $TS_S
}
disc_touch() {    # 选触摸节点; 输出 TDEV 与 TDEV_HOW(cap|fallback)
  TDEV=; TDEV_HOW=
  TD_BEST=; TD_S=0
  for TD_E in /dev/input/event*; do
    [ -e "$TD_E" ] || continue
    TD_SC=$(touch_score "$TD_E")
    [ "$TD_SC" -gt "$TD_S" ] 2>/dev/null || continue
    TD_BEST=$TD_E; TD_S=$TD_SC
  done
  if [ -n "$TD_BEST" ]; then TDEV=$TD_BEST; TDEV_HOW=cap
  else TDEV=/dev/input/event8; TDEV_HOW=fallback; fi
}
tdev_ok() {       # $1 = 节点; 0 = 确实是可用的触摸设备
  case "$1" in /dev/input/*) ;; *) return 1;; esac
  [ -e "$1" ] || return 1
  [ "$(touch_score "$1")" -gt 0 ] 2>/dev/null
}
# ---- TDEV_DISC_END ----

# 设备解析: 在当前 shell 内设置 TDEV (须直接调用, 不能放 $(...) 子 shell 里)
disc_tdev() {
  TDEV=; BDEV=; PDEV=
  BID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
  if [ -f $M/dev.conf ] && grep -q "BID=$BID" $M/dev.conf 2>/dev/null; then
    . $M/dev.conf 2>/dev/null
  fi
  # event 编号跨启动可能复用；缓存节点存在不等于仍是触摸屏，按能力复核。
  if [ -n "$TDEV" ] && [ -e "$TDEV" ]; then
    case "$TDEV" in
      /dev/input/*)
        tdev_ok "$TDEV" || TDEV=
        ;;
    esac
  else
    TDEV=
  fi
  [ -n "$TDEV" ] || disc_touch
}

# 设备几何: 当前 shell 内设置 K/SW/SH (像素宽/高)。K = 轴max / 屏宽SW, 自适应。
disc_geo() {
  K=100
  SW=$(sed -n 's/^SW=\([0-9][0-9]*\).*/\1/p' $M/water.sh 2>/dev/null | head -1)
  case "$SW" in ''|*[!0-9]*) SW=1220;; esac
  SH=$(sed -n 's/^SH=\([0-9][0-9]*\).*/\1/p' $M/water.sh 2>/dev/null | head -1)
  case "$SH" in ''|*[!0-9]*) SH=2656;; esac
  # 设备档案覆盖: DEV_APPLY=0(默认, 17 Pro)时本段不执行, SW/SH 就是 water.sh 的实测值。
  # 覆盖值要求「唯一 + 纯数字 + 下限」, 不合格就保留上面已经兜底好的值。
  # 重复键视为歧义配置: head -1 会让「后面追加一行」悄悄改掉生效值, 不接受这种写法。
  DEVCONF=/data/adb/icbc_water/device.conf
  devpick() {
    [ -f "$DEVCONF" ] || return 0
    [ "$(grep -c "^$1=" "$DEVCONF" 2>/dev/null)" = "1" ] || return 0
    sed -n "s/^$1=\([0-9][0-9]*\)$/\1/p" "$DEVCONF" 2>/dev/null | head -1
  }
  if [ "$(grep -c '^DEV_APPLY=' "$DEVCONF" 2>/dev/null)" = "1" ] \
     && [ "$(sed -n 's/^DEV_APPLY=\(1\)$/1/p' "$DEVCONF" 2>/dev/null | head -1)" = "1" ]; then
    DV_SW=$(devpick DEV_SW)
    DV_SH=$(devpick DEV_SH)
    if [ -n "$DV_SW" ] && [ "$DV_SW" -ge 300 ] 2>/dev/null; then SW=$DV_SW; fi
    if [ -n "$DV_SH" ] && [ "$DV_SH" -ge 300 ] 2>/dev/null; then SH=$DV_SH; fi
  fi
  if [ -n "$TDEV" ] && [ -e "$TDEV" ]; then
    P=$(getevent -p $TDEV 2>/dev/null)
    # getevent -p 的 ABS 摘要行可能同时列出 0035/0036；必须取
    # 0035:/0036: 的明细行，不能把摘要行误当成 max 行。
    MX=$(printf '%s\n' "$P" | grep -A2 -m1 -E 'ABS_MT_POSITION_X|(^|[[:space:]])0035[[:space:]]*:' | grep -m1 'max' | sed -E 's/.*max[^0-9]*([0-9]+).*/\1/')
    MY=$(printf '%s\n' "$P" | grep -A2 -m1 -E 'ABS_MT_POSITION_Y|(^|[[:space:]])0036[[:space:]]*:' | grep -m1 'max' | sed -E 's/.*max[^0-9]*([0-9]+).*/\1/')
    case "$MX" in ''|*[!0-9]*) MX=;; esac
    case "$MY" in ''|*[!0-9]*) MY=;; esac
    if [ -n "$MX" ] && [ "$MX" -gt 20000 ] 2>/dev/null; then
      K=$(( MX / SW ))
      [ $K -lt 1 ] && K=100
    fi
    # SH 是显示区高度，不是触摸面板 overscan 的轴 max；保留 water.sh 的
    # 已校准显示尺寸，避免 MY/K 把底部手势区错误地下移。
  fi
}

# 系统手势区过滤: 起点在底部导航条/左右边缘的 sw 丢弃 (MIUI 手势导航)
zone_sw() {  # 入参 SX SY; 命中返回 1 (丢弃), 未命中返回 0
  SX=$1; SY=$2
  [ "$SX" -le 60 ] && return 1          # 左边缘返回手势(含边界)
  [ "$SX" -ge $(( SW - 60 )) ] && return 1   # 右边缘返回手势(含边界)
  [ "$SY" -gt $(( SH - 130 )) ] && return 1  # 底部上滑回桌面/任务
  return 0
}

istate() {  # 0=屏幕亮且未锁(可录) 1=暂停(锁屏/暗屏/状态未知)
  P=$(dumpsys power 2>/dev/null)
  case "$P" in *mWakefulness=Awake*) ;; *) echo 1; return;; esac
  W=$(dumpsys window 2>/dev/null)
  if printf '%s' "$W" | grep -qE 'mShowingLockscreen=true|mDreamingLockscreen=true|isStatusBarKeyguard=true'; then
    echo 1; return
  fi
  # 无法读取锁屏服务时 fail-closed，避免把未知状态录成当前画面。
  if ! printf '%s' "$W" | grep -qE 'mShowingLockscreen=|mDreamingLockscreen=|isStatusBarKeyguard=|mCurrentFocus|mFocusedApp|WindowManager|Window #'; then
    echo 1; return
  fi
  echo 0
}

fg_pkg() {  # 当前前台包名 (无则空); 统一只返回包名，不把组件名/设备行当包名
  L=$(dumpsys activity activities 2>/dev/null | grep -m1 'topResumedActivity')
  if [ -z "$L" ]; then
    L=$(dumpsys activity activities 2>/dev/null | grep -m1 -E 'topActivity=|mResumedActivity|mFocusedActivity')
  fi
  case "$L" in
    ''|*null*) L=$(dumpsys window windows 2>/dev/null | grep -m1 -E 'mCurrentFocus|mFocusedApp');;
  esac
  [ -n "$L" ] || return

  # 先按字段取第一个用户 ID 后的包名。不能用 sed 的贪婪 .*，否则
  # HyperOS 的 isolated 进程(u0_a123)会把后面的 taskId 当成包名。
  R=$(printf '%s\n' "$L" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^u[0-9][0-9]*(_a[0-9][0-9]*)?$/ && i < NF) {
        print $(i + 1); exit
      }
    }
  }')
  if [ -z "$R" ]; then
    # 没有 user id 时，从带组件分隔符的字段取包名。
    R=$(printf '%s\n' "$L" | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i ~ /\/.*/ && $i !~ /^ActivityRecord/) {
          split($i, a, "/"); print a[1]; exit
        }
      }
    }')
  fi
  if [ -n "$R" ]; then
    R=${R%%/*}
    case "$R" in ''|*[!A-Za-z0-9._-]*) return;; esac
    printf '%s\n' "$R"
    return
  fi

  # 最后的兼容格式：ActivityRecord{... package/component。
  R=$(printf '%s\n' "$L" | sed -E 's/.*(topResumedActivity|topActivity|mResumedActivity|mFocusedActivity|mCurrentFocus|mFocusedApp)=[^ ]+ ([^ }/]+).*/\2/')
  case "$R" in ''|*[!A-Za-z0-9._-]*) return;; esac
  printf '%s\n' "$R"
}

# App 绑定模式允许的瞬时覆盖层。这里用精确包名，避免把组件/设备字段误当包名。
app_fg_ok() {
  case "$1" in
    "$PKG"|permissioncontroller|com.android.permissioncontroller|com.android.systemui|com.android.settings) return 0;;
  esac
  return 1
}

# 返回手势的起点在系统左右边缘。App 绑定模式保留它；裸录仍由 zone_sw 丢弃。
edge_sw() {
  [ -n "$PTS" ] || return 1
  [ "$EDGE_MOVE" -eq 1 ] 2>/dev/null || return 1
  [ "$SX" -le 60 ] && return 0
  [ "$SX" -ge $(( SW - 60 )) ] && return 0
  return 1
}

# 单调秒: /proc/uptime 不随 NTP 校时跳变, 数值小, 32 位 $(( )) 也不溢出。
# 墙钟 (date +%s) 被 NTP 回拨时, NOW-LAST 变负, 所有节流闸一起冻住 —— 表现为
# 「app 打开了却一直识别不到」。时间戳只用于节流/耗时, 必须用单调钟。
ups() {
  read U _ < /proc/uptime 2>/dev/null
  if [ -n "$U" ]; then echo "${U%%.*}"; else date +%s; fi
}
now_ms() {
  R=$(date +%s%3N 2>/dev/null)
  # 某些 toybox date 不支持 %3N；避免把字面量 N 当成毫秒参与算术。
  if [ ${#R} -lt 13 ]; then R=$(date +%s)000; fi
  printf '%s\n' "$R"
}

px() {  # hex(可能带 0x/前导0) -> 十进制; 失败给 0
  V=${1#0x}
  case "$V" in
    ''|*[!0-9a-fA-F]*) echo 0;;
    *) printf '%d' "0x$V" 2>/dev/null || echo 0;;
  esac
}

coordok_rec() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  return 0
}

pointsok_rec() {
  [ "$#" -ge 2 ] 2>/dev/null || return 1
  while [ "$#" -ge 2 ]; do
    coordok_rec "$1" || return 1
    coordok_rec "$2" || return 1
    shift 2
  done
  [ "$#" -eq 0 ]
}

# 只统计完整、非负整数坐标的动作；空/损坏录制不能覆盖旧流程。
rec_count_rx() {
  RCF=$1; RCC=0
  [ -f "$RCF" ] || { echo 0; return; }
  while IFS= read -r RCL || [ -n "$RCL" ]; do
    RCR=${RCL#W[0-9]* }
    case "$RCR" in
      tap\ *) set -- $RCR; [ "$#" -eq 3 ] && coordok_rec "$2" && coordok_rec "$3" && RCC=$((RCC+1));;
      sw@*)
        set -- $RCR; RCD=${1#sw@}; shift
        case "$RCD" in ''|*[!0-9]*) ;; *) pointsok_rec "$@" && RCC=$((RCC+1));; esac
        ;;
      sw\ *) set -- $RCR; shift; pointsok_rec "$@" && RCC=$((RCC+1));;
    esac
  done < "$RCF"
  echo "$RCC"
}

# 动作落盘: 手势完成瞬间前台复查(app绑定) + 系统手势区过滤(裸录)
put_gesture() {
  # 在任何前台查询前先取动作完成时刻; fg_pkg 可能耗时几十/上百ms,
  # 若放查询之后会把 sw 时长和动作时间戳人为拉长, 回放节奏失真。
  NOW=$(now_ms)
  MS=$(( NOW - T0 ))
  # 抬手前再核对一次屏幕状态，避免恰好在锁屏/暗屏边界把最后一下误存。
  if [ "$(istate)" != "0" ]; then
    log "PUT_SKIP 锁屏/暗屏时完成手势 起点$SX,$SY"
    return
  fi
  # app 绑定: 抬手瞬间复查前台。普通动作仍严格要求目标 App/允许的覆盖层；
  # 但左右边缘返回在抬手前必然把前台切回上一个页面，不能再用“抬手后包名”
  # 把它误判成离开 App。对边缘横滑改用按下瞬间已经确认过的归属。
  DIFF=0
  if [ $APPAWARE -eq 1 ]; then
    FG_NOW=$(fg_pkg)
    if app_fg_ok "$FG_NOW"; then
      :
    elif [ "$TOUCH_OK" -eq 1 ] && edge_sw; then
      log "PUT_EDGE 保留左右边缘返回 起点$SX,$SY 前台=$FG_NOW"
      # 返回后先暂停，避免下一次触摸落到上一个页面；回到目标 App 后自动恢复。
      APP_PAUSE=1
    else
      DIFF=1
    fi
  fi
  if [ $DIFF -eq 1 ]; then
    APP_PAUSE=1
    log "PUT_SKIP 手势完成时已离开目标app($PKG) 起点$SX,$SY"
    log "PAUSE 离开目标app (手势完成复查)"
    return
  fi
  if [ -z "$PTS" ]; then
    echo "W$MS tap $SX $SY" >> $TMP
  else
    # sw@DUR = 该滑动真实耗时ms (回放按它贴回原速度, 边缘返回需快速fling才触发)
    DUR=$(( NOW - TDOWN ))
    [ "$DUR" -lt 1 ] 2>/dev/null && DUR=1
    if [ $APPAWARE -eq 1 ]; then
      # app 绑定: 位置不限(含左/右边缘返回与底部上滑返回), 由上方完成时前台复查裁决
      echo "W$MS sw@$DUR $SX $SY $PTS $X $Y" >> $TMP
    elif [ "${ZONEFILT:-1}" = "1" ] && ! zone_sw $SX $SY; then
      # 指定包名之外的裸录只录普通区域滑动; zone_sw 返回 1 代表系统手势区。
      # 全场录取 (ZONEFILT=0) 走不到这里 —— 边缘返回/回桌面手势必须留住。
      log "ZONE_SKIP 系统手势区 sw 起点 $SX,$SY"
    else
      echo "W$MS sw@$DUR $SX $SY $PTS $X $Y" >> $TMP
    fi
  fi
}

# ---------- start ----------
start() {
  N=$1
  [ -n "$N" ] || { echo "ERR profile required"; exit 1; }
  slugok "$N" || { echo "ERR bad profile name"; exit 1; }
  CDIR=$PFX/$N
  [ -d "$CDIR" ] || { echo "ERR no profile: $N"; exit 1; }
  acquire_start_lock || { echo "ERR another start in progress"; exit 1; }
  trap 'release_start_lock' 0
  if replay_busy; then
    echo "ERR replay in progress"
    exit 1
  fi
  if [ -f $PIDF ]; then
    OLD_PID=$(cat $PIDF 2>/dev/null)
    case "$OLD_PID" in
      ''|*[!0-9]*) rm -f $PIDF $NAME;;
      *)
        if kill -0 "$OLD_PID" 2>/dev/null; then
          OLD_CMD=$(tr '\000' ' ' < "/proc/$OLD_PID/cmdline" 2>/dev/null)
          case "$OLD_CMD" in
            *record.sh*"_daemon"*) echo "ERR already recording pid=$OLD_PID"; exit 1;;
            *) rm -f $PIDF $NAME;;
          esac
        else
          rm -f $PIDF $NAME
        fi
        ;;
    esac
  fi
  # 起不来的两种硬原因先自己拦下, 不让它们伪装成一句「start failed」。
  command -v setsid >/dev/null 2>&1 || { echo "ERR start failed: PATH 里没有 setsid"; exit 1; }
  command -v getevent >/dev/null 2>&1 || { echo "ERR start failed: PATH 里没有 getevent"; exit 1; }
  rm -f $TMP
  rm -f "$BASE"/rec.evt.fifo.* 2>/dev/null   # 上次 daemon 被 kill -9 可能留下的事件 FIFO
  # 后台 daemon (setsid 脱离, 退出终端不影响; daemon 自写 pid 到 $PIDF)
  # [ -f ] 先判再读: 全新安装还没有 rec.log, 直接 `wc -l < $LOG` 会由 shell 抢在
  # 2>/dev/null 生效之前往 stderr 漏一句 "cannot open ... rec.log"。
  LOGN0=0
  [ -f "$LOG" ] && LOGN0=$(wc -l < "$LOG" 2>/dev/null)
  setsid sh $M/record.sh _daemon $N </dev/null >>$LOG 2>&1 &
  sleep 1
  if [ -f $PIDF ] && kill -0 $(cat $PIDF 2>/dev/null) 2>/dev/null; then
    log "REC_START $N"
    echo "REC_START $N pid=$(cat $PIDF)"
  else
    # 把 daemon 的真实死因带出来: 老版只回一句 ERR start failed, 用户报障时我们看不到
    # rec.log, 等于没有线索 —— 真机上「几个人说没法录取」就卡在这一步排查不下去。
    RECWHY=$(tail -n +$(( ${LOGN0:-0} + 1 )) "$LOG" 2>/dev/null | grep -v ' RAW[0-9]' | grep -v '^$' | tail -2)
    case "$RECWHY" in
      '') echo "ERR start failed: 后台没起来也没留日志, 请把 'sh record.sh start <任务>' 的输出发给作者";;
      *)  echo "ERR start failed: $(printf '%s\n' "$RECWHY" | tail -1 | sed 's/^[0-9]*-[0-9]* //')";;
    esac
    exit 1
  fi
}

# ---------- 后端 ----------
_daemon() {
  N=$1
  echo $$ > $PIDF
  echo "$N" > $NAME
  CDIR=$PFX/$N
  P_TYPE=script; P_PKG=; P_NAME=; P_SCOPE=
  [ -f $CDIR/conf ] && . $CDIR/conf 2>/dev/null
  PKG=$P_PKG
  # 录制型 profile 的空包名才表示裸录；脚本型/旧配置缺包名回退工行。
  if [ "$P_TYPE" != "record" ] && [ -z "$PKG" ]; then PKG=com.icbc; fi
  # 录制方式 (P_SCOPE): 空/pkg = 指定包名录取(核心路径, 上面原样保留);
  # all = 全场录取 —— 不绑定包名、不因离开某个 app 暂停, 连系统手势区的滑动也照录,
  # 因为「回桌面 / 边缘返回」本身就是跨 App 流程的一部分, 过滤掉回放就断了。
  ZONEFILT=1
  if [ "$P_SCOPE" = "all" ]; then
    PKG=
    ZONEFILT=0
  fi
  disc_tdev
  [ -e "$TDEV" ] || { log "FATAL 触摸设备不可用: $TDEV"; exit 1; }
  disc_geo
  chmod 600 "$LOG" "$TMP" 2>/dev/null
  log "DAEMON start N=$N K=$K TDEV=$TDEV PKG=$PKG SCOPE=${P_SCOPE:-pkg} SW=$SW SH=$SH MX=${MX:-} MY=${MY:-}"
  # 录制期间保持屏幕常亮 (否则录到一半超时锁屏), stop 时恢复
  STAY0=$(dumpsys power 2>/dev/null | grep -m1 'mStayOn=' | sed 's/.*mStayOn=\([^ ]*\).*/\1/')
  case "$STAY0" in true|false|usb|ac|wireless) ;; *) STAY0=false;; esac
  echo "$STAY0" > $BASE/rec.stayon 2>/dev/null
  chmod 600 $BASE/rec.stayon 2>/dev/null
  svc power stayon true 2>/dev/null
  # 验证码: 录制期间起一个 worker 每 ~0.7 s 截屏检测, 发现就建 $CAP_FLAG 并自动求解,
  # 消失后删标志。worker 与本 daemon 同进程组, stop 的 kill -9 -PGID 会一并带走它。
  CAP_PID=; CAP_FLAG=$BASE/captcha.on; CAP_PAUSE=0
  rm -f "$CAP_FLAG" 2>/dev/null
  [ -f "$M/captcha/captcha.sh" ] && . "$M/captcha/captcha.sh"
  CAP_LOGF=$M/log.txt
  if command -v cap_start >/dev/null 2>&1 && cap_start record; then
    log "CAPTCHA_WATCH on pid=$CAP_PID (验证码出现时暂停录取并自动求解)"
  else
    log "CAPTCHA_WATCH off (开关关闭或未找到 Termux Python)"
  fi
  # 子进程异常退出时也恢复录制前常亮状态；stop 的 kill -9 仍由 stop 兜底。
  trap 'cap_stop 2>/dev/null; restore_rec_stayon' 0
  trap 'cap_stop 2>/dev/null; restore_rec_stayon; trap - 0; exit 143' 1 2 15
  T0=$(now_ms)
  TSTART=$(date +%s)
  ACTIVE=0; STARTED=0
  SX=0; SY=0; X=0; Y=0
  PTS=""
  TDOWN=$(now_ms)
  LASTX=-9999; LASTY=-9999
  PAUSED=$(istate)   # 启动时按真实屏幕状态初始化 (亮屏未锁=0 直接可录)
  APPAWARE=0; APP_PAUSE=0; READY=0; MISS=0; FGW=0
  TOUCH_OK=0; TOUCH_FG=; EDGE_MOVE=0; LAST_FG=
  if [ -n "$PKG" ]; then
    APPAWARE=1
    LAST_FG=$(fg_pkg)
    if [ "$LAST_FG" = "$PKG" ]; then
      READY=1; echo 1 > "$BASE/rec.ready"; log "READY 目标app已在前台, 开始录取"
    fi
  else
    READY=1; echo 1 > "$BASE/rec.ready"; log "READY 未设目标app, 亮屏即录"   # 未设 PKG = 亮屏即开录 (任意 app)
  fi
  : > $TMP
  # 写入录制几何头 #RX1, 供跨设备回放按比例换算坐标。
  # 写成 # 注释行是刻意的: replay 主循环跳过 # 开头的行, rec_count_rx 的动作统计
  # 只认 ^W[0-9]+, webctl 的 pacts 统计同样只认 ^W[0-9]+ —— 三处都不会把头当动作。
  # 老版本 replay 读到这个文件也只是照常跳过, 行为与现在完全一致(向后兼容)。
  RXH_DPI=
  if [ -n "$DEVCONF" ] && [ -f "$DEVCONF" ] \
     && [ "$(grep -c '^DEV_APPLY=' "$DEVCONF" 2>/dev/null)" = "1" ] \
     && [ "$(sed -n 's/^DEV_APPLY=\(1\)$/1/p' "$DEVCONF" 2>/dev/null | head -1)" = "1" ]; then
    RXH_DPI=$(sed -n 's/^DEV_DPI=\([0-9][0-9]*\)$/\1/p' "$DEVCONF" 2>/dev/null | head -1)
  fi
  if [ -n "$RXH_DPI" ]; then
    printf '#RX1 SW=%s SH=%s K=%s DPI=%s\n' "$SW" "$SH" "$K" "$RXH_DPI" >> $TMP
  else
    printf '#RX1 SW=%s SH=%s K=%s\n' "$SW" "$SH" "$K" >> $TMP
  fi
  CNT=0
  LASTCHK_S=0
  LASTTICK=$(ups)
  # 状态/前台复查: 事件流忙时按行触发, 空闲时由 read -t tick 每秒触发一次。
  # 抽成函数是因为旧版只在 getevent 事件里复查 —— 用户切到目标 app 后手指一停,
  # 事件流就静默, READY 永远翻不过来, 表现为「没识别到 app / 录不到任何动作」。
  rec_check() {
    NS=$(istate)
    if [ "$NS" -ne "$PAUSED" ]; then
      if [ "$NS" -eq 1 ]; then
        if [ $ACTIVE -eq 1 ]; then
          ACTIVE=0; STARTED=0
          log "PAUSE_TRUNC 放弃未完成手势 $SX,$SY"
        fi
        log "PAUSE 锁屏/暗屏"
      else
        T0=$(now_ms)
        log "RESUME 亮屏解锁"
      fi
      PAUSED=$NS
    fi
    if [ $APPAWARE -eq 1 ]; then
      FP=$(fg_pkg)
      LAST_FG=$FP
      if [ "$READY" = "0" ]; then
        # 诊断: 每20次检查(~6s)打一次前台返回值, 定位"识别不到app"
        FGW=$((FGW+1))
        if [ $((FGW % 20)) -eq 1 ]; then
          log "FGWAIT 前台=<${FP}> 目标=<${PKG}> 等待目标app到前台"
        fi
        # 非空 P_PKG 必须等目标 App；不能因前台解析暂时失败就偷偷改成全量裸录。
        # 这里只给出可见提示，状态仍保持等待，避免录到桌面/其它 App。
        if [ $(( $(date +%s) - TSTART )) -ge 45 ] && [ $((FGW % 20)) -eq 1 ]; then
          log "WAIT_APP 45s仍未识别目标app($PKG), 继续等待，不降级裸录"
        fi
      fi
      case "$FP" in
        "$PKG")
          # 目标app在前台
          MISS=0
          if [ "$READY" = "0" ]; then
            READY=1
            T0=$(now_ms)
            echo 1 > "$BASE/rec.ready"
            log "READY 目标app已到前台, 开始录取"
          elif [ "$APP_PAUSE" = "1" ]; then
            APP_PAUSE=0
            T0=$(now_ms)
            log "RESUME 回到目标app, 继续录取"
          fi
          ;;
        permissioncontroller|com.android.permissioncontroller|com.android.systemui|com.android.settings)
          # 权限弹窗/系统UI覆盖: 仍算目标app操作会话, 不停录不截断
          MISS=0
          ;;
        *)
          # 空结果或其它包不能证明仍在目标app；连续N次确认才真暂停。
          # 手势进行中不掐断，等抬手由 put_gesture 精确复查裁决。
          MISS=$((MISS+1))
          if [ "$READY" = "1" ] && [ "$APP_PAUSE" = "0" ] && [ $MISS -ge 3 ]; then
            if [ $ACTIVE -eq 1 ]; then
              log "PEND_QUIT 离开确认中但手势未完成, 等抬手裁决 起点$SX,$SY"
            else
              APP_PAUSE=1
              log "PAUSE 离开目标app (连续$MISS次确认)"
            fi
            MISS=0
          fi
          ;;
      esac
    fi
    # 检查完成后再记时间；dumpsys 较慢时不会让下一行立即重复检查。
    # 录制暂停 (锁屏/暗屏/不在目标 app/还在等 app) 时让验证码 worker 退避到 3 s 一次; 只在状态变化时写盘
    CAP_IDLE_N=0
    { [ "$PAUSED" = "1" ] || [ "$READY" = "0" ] || [ "$APP_PAUSE" = "1" ]; } && CAP_IDLE_N=1
    if [ -n "$CAP_PID" ] && [ "$CAP_IDLE_N" != "${CAP_IDLE:-0}" ]; then
      CAP_IDLE=$CAP_IDLE_N
      if [ "$CAP_IDLE" = "1" ]; then : > "$BASE/captcha.idle"; else rm -f "$BASE/captcha.idle"; fi
    fi
  }
  # 事件源改走 FIFO + read -t: 有事件立即处理, 无事件每秒 tick 一次复查前台。
  # 快速边缘滑动可能只有几十行, 频繁 dumpsys 会把 getevent 消费拖慢; 行数条件
  # 只兜住密集事件, 空闲场景统一交给 tick (>=900ms 才复查, 不额外增加 dumpsys 频率)。
  EVFIFO=$BASE/rec.evt.fifo.$$
  rm -f "$EVFIFO"
  mkfifo "$EVFIFO" 2>/dev/null || { log "FATAL mkfifo 不可用, 无法建立事件管道"; exit 1; }
  getevent -t $TDEV > "$EVFIFO" 2>/dev/null &
  GEV_PID=$!
  exec 9< "$EVFIFO"
  rm -f "$EVFIFO"   # 路径即删: 读写两端靠已打开的 fd 继续通信, 退出自动回收
  while :; do
    # mksh read -t: 有数据=0; 超时=142; EOF=1
    IFS= read -r -t 1 line <&9
    RC=$?
    if [ "$RC" -eq 1 ]; then
      break   # getevent 结束
    fi
    if [ "$RC" -eq 142 ]; then
      # 空闲 tick: 手指一停事件流就静默, 这里每秒复查一次屏幕/前台,
      # 让「切到目标 app 后停手」也能翻转 READY, 并即时撤销验证码 worker 的 idle。
      NOW_S=$(ups)
      if [ $(( NOW_S - LASTTICK )) -ge 1 ]; then
        LASTTICK=$NOW_S
        rec_check
      fi
      continue
    fi
    CNT=$((CNT+1))
    # 原始事件采样: 前6行打日志, 便于核对 getevent 真实输出格式
    if [ $CNT -le 6 ]; then
      log "RAW$CNT $line"
    fi
    # 事件足够密时按行触发; 行数少(快速滑动只有几十行)时仍由空闲 tick 兜底复查。
    # 节流用单调秒: 32 位 sh 里毫秒值会溢出, 墙钟会被 NTP 回拨冻住, 12 行除数已提供背压。
    if [ "$CNT" -eq 1 ] || { [ $((CNT % 12)) -eq 0 ] && [ $(( $(ups) - LASTCHK_S )) -ge 1 ]; }; then
      LASTCHK_S=$(ups)
      rec_check
    fi
    # 验证码在屏 (worker 建的标志): 暂停录取。按下发生在标志存在期间的手势一律不录
    # (含 worker 自己的 input 注入 —— 它走 InputManager 不经 $TDEV, 这里再兜一层);
    # 标志出现前已按下的手势照常收尾。(CAPGATE 段由回归第 13 节抠出来模拟)
    # ---- CAPGATE_BEGIN ----
    # worker 被系统杀掉 (如 OOM) 时来不及删标志, 不能让录制永远停在暂停
    if [ -f "$CAP_FLAG" ] && [ -n "$CAP_PID" ] && ! kill -0 "$CAP_PID" 2>/dev/null; then
      rm -f "$CAP_FLAG"
      log "CAPTCHA worker 已退出, 清掉残留标志"
    fi
    if [ -f "$CAP_FLAG" ]; then
      if [ "$CAP_PAUSE" = "0" ]; then
        CAP_PAUSE=1
        log "PAUSE 验证码 (自动求解中, 期间新手势不录)"
      fi
    elif [ "$CAP_PAUSE" = "1" ]; then
      CAP_PAUSE=0
      log "RESUME 验证码已消失, 继续录取"
    fi
    [ "$CAP_PAUSE" = "1" ] && [ $ACTIVE -eq 0 ] && continue
    # ---- CAPGATE_END ----
    [ "$PAUSED" = "1" ] && continue
    [ "$READY" = "0" ] && continue
    [ "$APP_PAUSE" = "1" ] && continue

    # getevent -t 可能输出: [timestamp] /dev/input/eventN: TYPE CODE VALUE；
    # 也可能省略设备路径。先去掉时间戳/路径，再取最后三个字段，避免把
    # /dev/input/eventN: 误当成 TYPE 而漏录所有真实动作。
    DATA=${line#*] }
    case "$DATA" in
      *': '*) DATA=${DATA##*: };;
    esac
    set -- $DATA
    T=$1; C=$2; V=$3
    case "$T" in
      0000|EV_SYN)
        # 内核通知用户态此前丢帧时，混用两帧坐标会生成错误手势；直接丢弃当前手势。
        case "$C" in
          0003|SYN_DROPPED)
            if [ $ACTIVE -eq 1 ]; then
              log "SYN_DROPPED 放弃不完整手势 $SX,$SY"
              ACTIVE=0; STARTED=0; PTS=""
              TOUCH_OK=0; EDGE_MOVE=0
            fi
            ;;
        esac
        ;;
      0003|EV_ABS)   # ABS
        case "$C" in
          0035|ABS_MT_POSITION_X)   # X
            X=$(( $(px $V) / K ))
            # 该触摸驱动的同一采样帧是 X 后 Y；等 Y 到达后再采样，
            # 避免把新 X 与上一帧旧 Y 配成中间点，导致斜向/竖向滑动轨迹失真。
            ;;
          0036|ABS_MT_POSITION_Y)   # Y
            Y=$(( $(px $V) / K ))
            if [ $ACTIVE -eq 1 ] && [ $STARTED -eq 0 ]; then
              # 同帧 X,Y 到齐才定起点 (BTN_TOUCH 先于坐标到达, 按下瞬间取不到准确值)
              SX=$X; SY=$Y; LASTX=$X; LASTY=$Y; STARTED=1
            elif [ $ACTIVE -eq 1 ] && [ $STARTED -eq 1 ]; then
              DX=$((X-LASTX)); DY=$((Y-LASTY))
              ADX=$((X-SX)); [ "$ADX" -lt 0 ] && ADX=$(( -ADX ))
              [ "$ADX" -ge 20 ] && EDGE_MOVE=1
              if [ $(( DX*DX + DY*DY )) -ge 100 ] && { [ "$X" -ne "$LASTX" ] || [ "$Y" -ne "$LASTY" ]; }; then
                if [ -n "$PTS" ]; then PTS="$PTS $X $Y"; else PTS="$X $Y"; fi
                LASTX=$X; LASTY=$Y
              fi
            fi
            ;;
          0039|ABS_MT_TRACKING_ID)  # 手指抬起信号
            [ "$V" = "ffffffff" ] && UP=1 || UP=0
            if [ "$UP" = "1" ] && [ $ACTIVE -eq 1 ]; then
              ACTIVE=0; STARTED=0
              put_gesture
            fi
            ;;
        esac
        ;;
      0001|EV_KEY)   # KEY
        case "$C" in
          014a|BTN_TOUCH)  # 触摸键
            case "$V" in
              00000001|DOWN)
                # 按下
                ACTIVE=1; STARTED=0; PTS=""
                TOUCH_OK=0; TOUCH_FG=; EDGE_MOVE=0
                TDOWN=$(now_ms)   # 手势起始时刻(算 sw 真实耗时, 回放贴原速度)
                if [ $APPAWARE -eq 1 ]; then
                  # 返回手势完成前后台会切换；复用最近一次前台采样，避免在
                  # BTN_TOUCH 事件流中阻塞 dumpsys（快速边缘滑动的时序不能被打断）。
                  TOUCH_FG=$LAST_FG
                  # 缓存为空/已不是允许包时才做一次按下前确认；正常目标 App
                  # 会话走零额外 dumpsys，避免快速边缘滑动被拖慢。
                  if ! app_fg_ok "$TOUCH_FG"; then TOUCH_FG=$(fg_pkg); fi
                  if app_fg_ok "$TOUCH_FG"; then TOUCH_OK=1; fi
                fi
                ;;
              00000000|UP)
                # 抬起: 落动作
                if [ $ACTIVE -eq 1 ]; then
                  ACTIVE=0
                  [ $STARTED -eq 0 ] && { SX=$X; SY=$Y; }   # 兜底: 坐标先于按下到达的驱动
                  STARTED=0
                  put_gesture
                fi
                ;;
            esac
            ;;
        esac
        ;;
    esac
  done
  if [ $ACTIVE -eq 1 ]; then
    ACTIVE=0
    log "END_TRUNC 放弃未完成手势 $SX,$SY"
  fi
  log "DAEMON end"
  # 正常退出时由 EXIT trap 收尾; 若 getevent 自行结束, 也恢复常亮状态
  cap_stop 2>/dev/null
  restore_rec_stayon
}

# ---------- stop ----------
stop() {
  N=$1
  [ -n "$N" ] || { echo "ERR profile required"; exit 1; }
  slugok "$N" || { echo "ERR bad profile name"; exit 1; }
  # 没有活动 owner 时绝不把全局临时动作归档到任意 profile。
  if [ ! -f "$PIDF" ]; then
    rm -f "$TMP" "$NAME" "$START_LOCK" 2>/dev/null
    echo "ERR no active recording"
    exit 1
  fi
  if [ -f $PIDF ]; then
    ACTIVE_NAME=$(cat $NAME 2>/dev/null)
    [ -n "$ACTIVE_NAME" ] || { echo "ERR recording state unknown"; exit 1; }
    if [ "$ACTIVE_NAME" != "$N" ]; then
      echo "ERR recording another profile: $ACTIVE_NAME"
      exit 1
    fi
    PID=$(cat $PIDF 2>/dev/null)
    case "$PID" in
      ''|*[!0-9]*) echo "ERR invalid recording pid"; exit 1;;
    esac
    if kill -0 "$PID" 2>/dev/null; then
      # PID 复用保护：只终止确认属于该录制 daemon 的进程组。
      CM=$(tr '\000' ' ' < "/proc/$PID/cmdline" 2>/dev/null)
      if [ -n "$CM" ]; then
        case "$CM" in
          *record.sh*"_daemon"*"$N"*) ;;
          *) echo "ERR pid ownership mismatch"; exit 1;;
        esac
      fi
      RPG=$(awk '{print $5}' "/proc/$PID/stat" 2>/dev/null)
      if [ "$RPG" = "$PID" ]; then
        kill -9 -"$PID" 2>/dev/null   # setsid 独立进程组
      else
        kill -9 "$PID" 2>/dev/null
      fi
    fi
    rm -f $PIDF
  fi
  # 兜底: 按命令行杀掉管道子壳/getevent (读取端消失后 getevent 会 SIGPIPE 自灭)
  pkill -9 -f "record.sh _daemon $N" 2>/dev/null
  # 验证码 worker 随进程组一起被杀, 来不及删自己的标志; 它若漏网也会在 0.7 s 内发现主人已死自行退出
  rm -f "$BASE/captcha.on" "$BASE/captcha.idle" "$BASE/rec.ready" 2>/dev/null
  sleep 0.6
  # 恢复录制前屏幕常亮状态
  restore_rec_stayon
  rm -f $NAME
  CDIR=$PFX/$N
  [ -d "$CDIR" ] || { echo "ERR no profile: $N"; exit 1; }
  CNT=$(rec_count_rx "$TMP")
  CNT=${CNT:-0}
  if [ "$CNT" -ge 1 ] 2>/dev/null; then
    AT=$CDIR/actions.rx.tmp.$$
    if cp "$TMP" "$AT" 2>/dev/null && chmod 600 "$AT" 2>/dev/null && mv "$AT" "$CDIR/actions.rx" 2>/dev/null; then
      rm -f $NAME
      log "REC_STOP $N actions=$CNT"
      echo "REC_STOP $N actions=$CNT -> $CDIR/actions.rx"
    else
      rm -f "$AT" 2>/dev/null
      rm -f "$CDIR/actions.rx" 2>/dev/null
      log "REC_STOP $N write-failed"
      echo "ERR write actions.rx"
      exit 1
    fi
  else
    # 空录制不能继续沿用旧 actions.rx，否则下次会误回放上一次流程。
    rm -f "$CDIR/actions.rx"
    rm -f $NAME
    log "REC_STOP $N empty"
    echo "REC_STOP $N empty (没有抓到有效动作)"
  fi
}

# ---------- status ----------
status() {
  if [ -f $PIDF ] && kill -0 $(cat $PIDF 2>/dev/null) 2>/dev/null; then
    echo "recording=yes pid=$(cat $PIDF) name=$(cat $NAME 2>/dev/null)"
    # ready: 0 = 还在等目标 app 到前台, 1 = 已在录取 (锁屏/离开 app 另由 state 表达)
    if [ -f "$BASE/rec.ready" ]; then echo "ready=1"; else echo "ready=0"; fi
    echo "state=$(istate)  # 0=录取中 1=暂停(锁屏)"
    CNT=$(rec_count_rx "$TMP")
    echo "actions=${CNT:-0}"
    grep -E 'DAEMON start|READY|PAUSE|RESUME' $LOG 2>/dev/null | tail -4
  else
    echo "recording=no"
  fi
}

case "$1" in
  start) start "$2";;
  stop)  stop "$2";;
  status) status;;
  _daemon) _daemon "$2";;
  *) echo "usage: record.sh start PROFILE|stop PROFILE|status"; exit 1;;
esac