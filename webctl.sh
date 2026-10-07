#!/system/bin/sh
# icbc_daily_water / webctl.sh v0.13.0 - WebUI 助手 (由 KSU 管理器 WebView 以 root 调用)
# 用法: webctl.sh status|setpin|setpattern|settime|setdays|setenable|setmode|setopen|
#        setsleep|setwatch|setcleanup|unlock|trigger[NAME]|restart|log|profiles|
#        profile add/addicbc/del/set|record start/stop/status|device get|set|detect
M=/data/adb/modules/icbc_daily_water
CFG=/data/adb/icbc_water/sched.conf
LOG=$M/log.txt
BASE=/data/adb/icbc_water
PFX=/data/adb/icbc_water/profiles
REC=$M/record.sh
# 内置工行任务的「用户已删除」标记: 有它就绝不重建(service.sh / customize.sh 都认)
NOICBC=$BASE/no_icbc
# 清理上次异常中断留下的配置临时文件；正式 PIN 只保存在 CFG。
rm -f "$CFG".tmp.* "$CFG".pin.* 2>/dev/null
cleanup_cfg_tmp() { rm -f "$CFG".tmp.* "$CFG".pin.* 2>/dev/null; }
trap 'cleanup_cfg_tmp' 0
trap 'cleanup_cfg_tmp; exit 143' 1 2 15

atomic_update() {  # FILE KEY VALUE; shell-only rewrite, same-directory mv
  AU_FILE=$1; AU_KEY=$2; AU_VAL=$3
  AU_TMP=$AU_FILE.tmp.$$
  rm -f "$AU_TMP" 2>/dev/null
  if ! ( umask 077; : > "$AU_TMP" ); then return 1; fi
  AU_FOUND=0
  if [ -f "$AU_FILE" ]; then
    while IFS= read -r AU_LINE || [ -n "$AU_LINE" ]; do
      case "$AU_LINE" in
        "$AU_KEY"=*) printf '%s=%s\n' "$AU_KEY" "$AU_VAL" >> "$AU_TMP"; AU_FOUND=1;;
        *) printf '%s\n' "$AU_LINE" >> "$AU_TMP";;
      esac
    done < "$AU_FILE"
  fi
  [ "$AU_FOUND" -eq 1 ] || printf '%s=%s\n' "$AU_KEY" "$AU_VAL" >> "$AU_TMP"
  chmod 600 "$AU_TMP" 2>/dev/null || { rm -f "$AU_TMP" 2>/dev/null; return 1; }
  if ! mv "$AU_TMP" "$AU_FILE" 2>/dev/null; then
    rm -f "$AU_TMP" 2>/dev/null
    return 1
  fi
  return 0
}

setval() {  # setval KEY VALUE  (值经调用方白名单校验)
  K=$1; V=$2
  if ! atomic_update "$CFG" "$K" "$V"; then
    echo "ERR write config"
    exit 1
  fi
  # PIN/图案只回显“已设置”，绝不能把明文带回 WebUI/API 或 shell 输出。
  # 图案是一串 1-9 的点序, 与 PIN 同等敏感 —— 泄露等于直接给出解锁方式。
  if [ "$K" = "PIN" ]; then
    echo "SET PIN=已设置"
  elif [ "$K" = "PATTERN" ]; then
    if [ -n "$V" ]; then echo "SET PATTERN=已设置"; else echo "SET PATTERN="; fi
  else
    echo "SET $K=$V"
  fi
}

# 每周执行日取值: 空(继承全局) / 单个 0(一天都不跑) / 1-7 严格递增无重复。
# 与 service.sh 的 days_shape 同一套规则, 两边都认才不会出现「界面存得下、调度不认」。
daysok() {
  [ -z "$1" ] && return 0
  [ "$1" = "0" ] && return 0
  case "$1" in *[!1-7]*) return 1;; esac
  DK=$1; DPV=0; DI=1
  while [ $DI -le ${#DK} ]; do
    DCV=$(printf '%s' "$DK" | cut -c $DI)
    [ "$DCV" -le "$DPV" ] && return 1
    DPV=$DCV
    DI=$((DI+1))
  done
  return 0
}

# 图案点序: 1-9 的数字, 长度 4-9, 不能重复 (Android 宫格最多 9 个点且每点只过一次)。
# 空值合法, 表示清除图案。
patternok() {
  [ -z "$1" ] && return 0
  case "$1" in *[!1-9]*) return 1;; esac
  [ ${#1} -lt 4 ] && return 1
  [ ${#1} -gt 9 ] && return 1
  PK=$1
  while [ -n "$PK" ]; do
    PC=$(printf '%s' "$PK" | cut -c1)
    PRE=$(printf '%s' "$PK" | cut -c2-)
    case "$PRE" in *"$PC"*) return 1;; esac
    PK=$PRE
  done
  return 0
}

# HHMM → 当日分钟数 (防前导0八进制坑, 非法值返回0)
hhmm2m() {
  case "$1" in
    [0-9][0-9][0-9][0-9])
      h=${1%??}; h=${h#0}; h=${h:-0}
      m=${1#??}; m=${m#0}; m=${m:-0}
      echo $(( h * 60 + m ));;
    *) echo 0;;
  esac
}

# profile 目录名/slug 校验: 空拒; 禁空白/斜杠/引号/壳元字符; 允中英数_横线; 长度<=24
slugok() {
  [ -n "$1" ] || return 1
  [ ${#1} -le 24 ] || return 1
  case "$1" in
    *' '*|*'/'*|*'\\'*) return 1;;
    *"'"*|*'"'*|*'`'*) return 1;;
    *'$'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*) return 1;;
    *'#'*|*'='*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'..'*|*'.') return 1;;
  esac
  # 允许 UTF-8 高字节，但拒绝换行/制表符等控制字节。
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}

# Android 包名白名单；空值是合法的“裸录/当前画面”模式。
pkgok() {
  [ -z "$1" ] && return 0
  case "$1" in *[!0-9A-Za-z_.]*) return 1;; esac
  return 0
}

# profile 显示名会写入 conf 并被 service source，拒绝空白/壳元字符/控制字节。
nameok() {
  [ -n "$1" ] || return 1
  [ ${#1} -le 32 ] || return 1
  case "$1" in
    *' '*|*'/'*|*'\\'*|*"'"*|*'"'*|*'$'*|*'`'*|*';'*|*'&'*|*'|'*|*'<'*|*'>'*) return 1;;
    *'('*|*')'*|*'!'*|*'*'*|*'?'*|*'['*|*']'*|*'{'*|*'}'*|*'#'*|*'='*) return 1;;
  esac
  if printf '%s' "$1" | LC_ALL=C grep -q '[[:cntrl:]]'; then return 1; fi
  return 0
}

coordok_web() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  return 0
}

pointsok_web() {
  [ "$#" -ge 2 ] 2>/dev/null || return 1
  while [ "$#" -ge 2 ]; do
    coordok_web "$1" || return 1
    coordok_web "$2" || return 1
    shift 2
  done
  [ "$#" -eq 0 ]
}

has_valid_actions() {
  AV_FILE=$1
  [ -f "$AV_FILE" ] || return 1
  while IFS= read -r AV_LINE || [ -n "$AV_LINE" ]; do
    AV_REST=${AV_LINE#W[0-9]* }
    case "$AV_REST" in
      tap\ *) set -- $AV_REST; [ "$#" -eq 3 ] && coordok_web "$2" && coordok_web "$3" && return 0;;
      sw@*)
        set -- $AV_REST; AV_DUR=${1#sw@}; shift
        case "$AV_DUR" in ''|*[!0-9]*) ;; *) pointsok_web "$@" && return 0;; esac
        ;;
      sw\ *) set -- $AV_REST; shift; pointsok_web "$@" && return 0;;
    esac
  done < "$AV_FILE"
  return 1
}

restart_svc() {
  for p in $(pgrep -f "$M/service.sh" 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    PG=$(awk '{print $5}' "/proc/$p/stat" 2>/dev/null)
    if [ "$PG" = "$p" ]; then
      kill -9 -"$p" 2>/dev/null
    else
      kill -9 "$p" 2>/dev/null
    fi
  done
  sleep 1
  # 独立会话全脱离启动, 避免随 WebUI 的 exec 会话结束被连带杀掉
  ( setsid sh $M/service.sh </dev/null >/dev/null 2>&1 & ) 2>/dev/null \
    || ( sh $M/service.sh </dev/null >/dev/null 2>&1 & )
  sleep 2
  pid=$(pgrep -f "$M/service.sh" 2>/dev/null | head -1)
  if [ -n "$pid" ]; then
    echo "SERVICE restarted pid=$pid"
  else
    echo "SERVICE restart-failed"
  fi
}

# 输出单个 profile 状态行 (webctl status 与 profiles 共用)
prof_line() {
  CD=$1
  PN=$(basename "$CD")
  P_NAME=; P_TYPE=; P_PKG=; P_SCHED=; P_ENABLE=; P_CLEANUP=; P_SCALE=
  P_DAYS=; P_SCOPE=; P_HOME=
  [ -f $CD/conf ] && . $CD/conf 2>/dev/null
  T0=$(date +%Y%m%d)
  PD=no
  [ -f $CD/state.txt ] && [ "$(cat $CD/state.txt 2>/dev/null)" = "$T0" ] && PD=yes
  PTRY=0
  [ -f $CD/try.txt ] && PTRY=$(cat $CD/try.txt 2>/dev/null)
  PACTS=0
  # sw@DUR 是新格式; 同时兼容旧 sw 空格格式
  [ -f $CD/actions.rx ] && PACTS=$(grep -cE '^W[0-9]+ (tap|sw@[0-9]+|sw)($| )' $CD/actions.rx 2>/dev/null)
  # pdays 空 = 跟随全局 SCHED_DAYS; pscope 空/ pkg = 指定包名录取, all = 全场录取
  echo "profile=$PN pname=${P_NAME:-$PN} ptype=${P_TYPE:-script} ppkg=${P_PKG:-} psched=${P_SCHED:-} penable=${P_ENABLE:-} pcleanup=${P_CLEANUP:-} pscale=${P_SCALE:-0} pdone=$PD ptry=$PTRY pacts=${PACTS:-0} pdays=${P_DAYS:-} pscope=${P_SCOPE:-pkg} phome=${P_HOME:-1}"
}

list_profiles() {
  mkdir -p $PFX 2>/dev/null
  for CD in $PFX/*; do
    [ -d "$CD" ] || continue
    prof_line "$CD"
  done
}

# ---------- 设备档案 (v0.11.0) ----------
# device.conf 里 DEV_APPLY 是总闸: 0 = 保持 17 Pro 的实测基线(默认), 1 = 用 DEV_* 覆盖。
# 这里只做读写与检测; 真正「应用」由 water.sh / service.sh / record.sh / replay.sh 各自在
# 运行时读取并做纯数字+唯一性校验, 校验不过就保留原值。
DEV_DIR=/data/adb/icbc_water
DEV_FILE=$DEV_DIR/device.conf

# 读单个键(只认纯 ASCII 标签; 重复键视为歧义, 返回空)
dev_read() {
  [ -f "$DEV_FILE" ] || return 0
  [ "$(grep -c "^$1=" "$DEV_FILE" 2>/dev/null)" = "1" ] || return 0
  sed -n "s/^$1=\(.*\)$/\1/p" "$DEV_FILE" 2>/dev/null | head -1
}

# 删掉一个键。atomic_update 只会「设值」, 关总闸时要把上一台机器的分辨率整个删掉:
# 否则注释写「清掉」而实现只改不删, 下次打开界面读到的仍是旧机器的 1440x3200。
dev_clear() {
  [ -f "$DEV_FILE" ] || return 0
  DC_TMP=$DEV_FILE.tmp.$$
  rm -f "$DC_TMP" 2>/dev/null
  if ! ( umask 077; : > "$DC_TMP" ); then return 1; fi
  while IFS= read -r DC_LINE || [ -n "$DC_LINE" ]; do
    case "$DC_LINE" in
      "$1="*) ;;
      *) printf '%s\n' "$DC_LINE" >> "$DC_TMP";;
    esac
  done < "$DEV_FILE"
  chmod 600 "$DC_TMP" 2>/dev/null || { rm -f "$DC_TMP" 2>/dev/null; return 1; }
  if ! mv "$DC_TMP" "$DEV_FILE" 2>/dev/null; then
    rm -f "$DC_TMP" 2>/dev/null
    return 1
  fi
  return 0
}

dev_get() {
  echo "=== 设备档案 ==="
  DEV_ON=0
  if [ -f "$DEV_FILE" ]; then
    for DK in DEV_APPLY DEV_MODEL DEV_LABEL DEV_STATUS DEV_SW DEV_SH DEV_D DEV_DPI \
              DEV_PIN_X0 DEV_PIN_Y0 DEV_PIN_DX DEV_PIN_DY \
              DEV_PAT_X0 DEV_PAT_Y0 DEV_PAT_DX DEV_PAT_DY; do
      DV=$(dev_read "$DK")
      [ -n "$DV" ] && echo "$DK=$DV"
    done
    [ "$(dev_read DEV_APPLY)" = "1" ] && DEV_ON=1
  else
    echo "(no device.conf)"
  fi
  echo "DEV_APPLIED=$DEV_ON"
}

# 写入: 白名单 + 逐项校验。数值键只收纯数字, 标签键只收 [A-Za-z0-9_.-]。
# 标签键的「空格 <-> 下划线」转换由界面负责(devToStore/devParse), 这里不替它猜:
# device.conf 是多处脚本共读的纯 ASCII 键值文件, 存空格会让下游按空白切词读串。
# DEV_APPLY=0 时把数值键整个删掉, 避免留着上一台机器的数据误导人。
dev_set() {
  mkdir -p "$DEV_DIR" 2>/dev/null
  # 先按参数逐项校验, 全部通过才落盘, 避免半途中断留下半个配置
  DS_PEND=
  DS_APPLY=
  for KV in "$@"; do
    case "$KV" in
      *=*) DK=${KV%%=*}; DV=${KV#*=}
          DV=$(printf '%s' "$DV" | tr -d '\r\n') ;;
      *) continue ;;
    esac
    case "$DK" in
      DEV_APPLY)
        case "$DV" in 0|1) DS_APPLY=$DV; DS_PEND="$DS_PEND $DK=$DV";; *) echo "ERR apply 0/1"; exit 1;; esac ;;
      DEV_SW|DEV_SH|DEV_D|DEV_DPI|DEV_PIN_X0|DEV_PIN_Y0|DEV_PIN_DX|DEV_PIN_DY|\
      DEV_PAT_X0|DEV_PAT_Y0|DEV_PAT_DX|DEV_PAT_DY)
        # 纯数字, 且不超长(防溢出); DEV_D 允许 0
        case "$DV" in
          ''|*[!0-9]*) echo "ERR $DK 必须是纯数字"; exit 1;;
        esac
        [ ${#DV} -gt 18 ] && { echo "ERR $DK 数值过长"; exit 1; }
        DS_PEND="$DS_PEND $DK=$DV" ;;
      DEV_MODEL|DEV_LABEL|DEV_STATUS)
        # 纯 ASCII 短标签, 不允许空白与引号/反斜杠
        case "$DV" in
          ''|*[!A-Za-z0-9_.-]*) echo "ERR $DK 只允许字母数字 _ . -"; exit 1;;
        esac
        [ ${#DV} -gt 40 ] && { echo "ERR $DK 过长"; exit 1; }
        DS_PEND="$DS_PEND $DK=$DV" ;;
      *) echo "ERR unknown key $DK"; exit 1;;
    esac
  done
  [ -n "$DS_PEND" ] || { echo "ERR nothing to set"; exit 1; }
  for KV in $DS_PEND; do
    atomic_update "$DEV_FILE" "${KV%%=*}" "${KV#*=}" || { echo "ERR write device.conf"; exit 1; }
  done
  # 总闸关掉时, 把数值键整个删掉: 界面上就不会残留上一台机器的分辨率。
  # 只有 device.conf 里还没有显示名时才回落 17 Pro —— 用户手填的名字不能被覆盖,
  # 旧版无条件 atomic_update DEV_LABEL, 等于把用户填的名字一关总闸就抹掉。
  if [ "$DS_APPLY" = "0" ]; then
    atomic_update "$DEV_FILE" DEV_MODEL 17pro
    atomic_update "$DEV_FILE" DEV_STATUS stable
    [ -n "$(dev_read DEV_LABEL)" ] || atomic_update "$DEV_FILE" DEV_LABEL Xiaomi_17_Pro
    for DCK in DEV_SW DEV_SH DEV_D DEV_DPI DEV_PIN_X0 DEV_PIN_Y0 DEV_PIN_DX DEV_PIN_DY \
               DEV_PAT_X0 DEV_PAT_Y0 DEV_PAT_DX DEV_PAT_DY; do
      dev_clear "$DCK"
    done
  fi
  dev_get
}

# 自动检测: 只读 wm size / wm density / dumpsys display, 不写任何文件。
# 检测结果只回显, 由界面预填给用户确认后再保存 —— 不做「检测到就直接生效」。
dev_detect() {
  echo "=== 自动检测 ==="
  DSW=; DSH=; DDP=
  DSZ=$(wm size 2>/dev/null | grep -m1 'Override size')
  [ -z "$DSZ" ] && DSZ=$(wm size 2>/dev/null | grep -m1 'Physical size')
  if [ -n "$DSZ" ]; then
    DSW=$(printf '%s' "$DSZ" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)x\([0-9][0-9]*\).*/\1/p')
    DSH=$(printf '%s' "$DSZ" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)x\([0-9][0-9]*\).*/\2/p')
    [ -n "$DSW" ] && echo "DEV_SW=$DSW"
    [ -n "$DSH" ] && echo "DEV_SH=$DSH"
  fi
  DD=$(wm density 2>/dev/null | grep -m1 'Override density')
  [ -z "$DD" ] && DD=$(wm density 2>/dev/null | grep -m1 'Physical density')
  DDP=$(printf '%s' "$DD" | sed -n 's/.*[^0-9]\([0-9][0-9]*\).*/\1/p')
  [ -n "$DDP" ] && echo "DEV_DPI=$DDP"
  # 显示 ID: 多数机型的 screencap -d 用 0, 探测不到就报 0, 由用户核对。
  # 只在真拿到尺寸时才报 —— 检测整体失败时若仍回 0, 会把用户手填的显示 ID 抹成 0。
  [ -n "$DSW" ] && echo "DEV_D=0"
  # 锁屏键盘宫格无法自动可靠识别, 明确告知需要手动填。
  echo "DEV_PIN_HINT=manual"
  # 机型名尝试从 ro.product.model 取
  DMODEL=$(getprop ro.product.model 2>/dev/null | tr -d '\r\n' | sed 's/[^A-Za-z0-9_.-]/_/g')
  [ -n "$DMODEL" ] && echo "DEV_MODEL=$DMODEL"
  # 显示名取 marketname(带空格的真名), 同样压成存储形态; 拿不到就退回机型名。
  # 以前检测不回显示名, 界面就一直挂着 loadDevice 兜底的 'Xiaomi 17 Pro',
  # 保存出来的档案里「机型 M2102K1C、显示名 17 Pro」自相矛盾。
  DMARKET=$(getprop ro.product.marketname 2>/dev/null | tr -d '\r\n' | sed 's/[^A-Za-z0-9_.-]/_/g')
  [ -z "$DMARKET" ] && DMARKET=$DMODEL
  [ -n "$DMARKET" ] && echo "DEV_LABEL=$DMARKET"
  # DEV_DETECT 必须排在最后、且只在真拿到东西时才 ok。
  # 旧版在任何检测动作之前就无条件 echo DEV_DETECT=ok, wm size 拿不到值时
  # 界面照样提示「已检测到本机参数」, 用户据此去保存就会踩空。
  if [ -n "$DSW" ] || [ -n "$DSH" ] || [ -n "$DDP" ]; then
    echo "DEV_DETECT=ok"
  else
    echo "DEV_DETECT=none"
  fi
}

case "$1" in
  status)
    echo "=== 状态 ==="
    SVC=stopped
    pgrep -f "$M/service.sh" >/dev/null 2>&1 && SVC=running
    echo "service: $SVC"
    T=$(date +%Y%m%d)
    # DONE 看内置 icbc profile (脚本型工行浇水); FORCE 不写 => 可反复测试永不污染
    IDONE=no
    if [ -f $PFX/icbc/state.txt ] && [ "$(cat $PFX/icbc/state.txt 2>/dev/null)" = "$T" ]; then IDONE=yes; fi
    if [ "$IDONE" = "yes" ]; then
      echo "today: DONE"
    else
      echo "today: pending"
    fi
    ICT=0
    [ -f $PFX/icbc/try.txt ] && ICT=$(cat $PFX/icbc/try.txt 2>/dev/null)
    echo "fail_times: $ICT"
    # 内置工行任务在不在 (用户可能已删除): 界面据此决定要不要显示「恢复内置工行」
    if [ -f $PFX/icbc/conf ]; then echo "icbc_present=yes"; else echo "icbc_present=no"; fi
    if [ -f $CFG ]; then . $CFG; fi
    NOWT=$(date +%H%M)
    LAST=0
    [ -f $M/last.txt ] && LAST=$(cat $M/last.txt 2>/dev/null)
    I=$(( $(date +%s) - ${LAST:-0} ))
    [ $I -lt 0 ] && I=0
    A=0
    dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake' && A=1
    echo "=== 触发检查 ==="
    echo "svc=$SVC enable=${SCHED_ENABLE:-1} screen=$A now=$NOWT sched=$SCHED_TIME last_ago=$I"
    # 窗口: 内置工行定时 (到点后 60 分钟内, 跨零点衔接)
    NOWM_A=$(hhmm2m $NOWT); SCHEDM_A=$(hhmm2m $SCHED_TIME)
    W=0
    if [ $NOWM_A -ge $SCHEDM_A ] && [ $NOWM_A -le $((SCHEDM_A + 60)) ]; then W=1; fi
    if [ $SCHEDM_A -gt 1380 ] && [ $NOWM_A -le $((SCHEDM_A + 60 - 1440)) ]; then W=1; fi
    if [ $W -eq 1 ]; then echo "window_ok=yes"; else echo "window_ok=no"; fi
    if [ "$IDONE" = "yes" ]; then echo "done_ok=yes"; else echo "done_ok=no"; fi
    # 今天是不是执行日 (全局 SCHED_DAYS; 单个任务的 P_DAYS 各自看 profile 行)
    DOW=$(date +%u 2>/dev/null)
    DLIST=${SCHED_DAYS:-1234567}
    DAYOK=yes
    case "$DLIST" in
      ''|0) [ -n "$DLIST" ] && DAYOK=no;;
      *) case "$DLIST" in *"$DOW"*) :;; *) DAYOK=no;; esac;;
    esac
    echo "day=$DOW day_ok=$DAYOK sched_days=${DLIST}"
    echo "=== Profiles ==="
    list_profiles
    echo "=== 配置 ==="
    # 状态接口也必须脱敏 PIN 与图案点序；WebUI 不应能通过 stdout 读到明文。
    # 两条敏感键都在这一处统一替换成「已设置」/空, 不留第二条输出通道。
    if [ -f $CFG ]; then
      PINSET=$(sed -n 's/^PIN=//p' $CFG 2>/dev/null | head -1)
      PATSET=$(sed -n 's/^PATTERN=//p' $CFG 2>/dev/null | head -1)
      awk -v pinset="$PINSET" -v patset="$PATSET" '
        /^PIN=/    { print (pinset == "" ? "PIN=" : "PIN=已设置"); next }
        /^PATTERN=/{ print (patset == "" ? "PATTERN=" : "PATTERN=已设置"); next }
        { print }
      ' "$CFG" 2>/dev/null
    fi
    ;;
  setpin)
    # 只接受 KernelSU exec 的 env 通道；PIN 不进入命令字符串/进程参数。
    V=$WEBUI_PIN
    unset WEBUI_PIN
    V=$(printf '%s' "$V" | tr -d ' \t')
    case "$V" in
      ''|*[!0-9]*) echo "ERR pin must be digits"; exit 1;;
    esac
    if [ ${#V} -lt 4 ] || [ ${#V} -gt 8 ]; then echo "ERR pin length 4-8"; exit 1; fi
    setval PIN "$V"
    unset WEBUI_PIN V
    ;;
  setpattern)
    # 图案点序走 env 通道 (WEBUI_PATTERN), 与 PIN 同规: 不进命令字符串/进程参数。
    # 清空 = 取消图案解锁 (回到 PIN 或上滑)。
    V=$WEBUI_PATTERN
    unset WEBUI_PATTERN
    V=$(printf '%s' "$V" | tr -d ' \t')
    patternok "$V" || { echo "ERR pattern must be 4-9 distinct digits 1-9 (or empty to clear)"; exit 1; }
    setval PATTERN "$V"
    unset V
    ;;
  setdays)
    # 全局执行日: 空/0/升序 1-7 串。0 = 一周都不跑(定时整体停摆, 手动触发不受影响)
    V=$(printf '%s' "$2" | tr -d ' \t')
    daysok "$V" || { echo "ERR days 空=每天, 0=不跑, 或 1-7 升序串如 135"; exit 1; }
    setval SCHED_DAYS "$V"
    ;;
  settime)
    V=$(printf '%s' "$2" | tr -d ' \t')
    case "$V" in
      ''|*[!0-9]*) echo "ERR time must be HHMM"; exit 1;;
    esac
    if [ ${#V} -ne 4 ]; then echo "ERR time must be 4 digits e.g. 0730"; exit 1; fi
    HH=${V%??}; MM=${V#??}
    if [ "$HH" -gt 23 ] || [ "$MM" -gt 59 ]; then echo "ERR invalid HHMM"; exit 1; fi
    setval SCHED_TIME "$V"
    # 同步内置工行 profile 的 P_SCHED —— settime 是不是真的生效就看这一步。
    # 调度器取的是 PSCHED=${P_SCHED:-$SCHED_TIME}, 而内置 profile 一生下来就把
    # SCHED_TIME 快照进了 P_SCHED(service.sh ensure_profiles / customize.sh 安装时写),
    # 所以只写 SCHED_TIME 的话, 工行永远按安装那一刻的旧时间跑, 这条命令成空操作。
    # 四份 README 都拿 `webctl.sh settime 0730` 当命令行用法示例, 必须真生效。
    # 写 profile 而不是反过来删 P_SCHED: 一个 profile 有自己的 P_SCHED 是合法状态
    # (用户在 WebUI 里给它单独设过), 不能因为全局改动就把那层覆盖删掉。
    if [ -f "$PFX/icbc/conf" ]; then
      if ! atomic_update "$PFX/icbc/conf" P_SCHED "$V"; then
        echo "ERR write icbc profile sched"
        exit 1
      fi
      echo "SET P_SCHED=$V (icbc)"
    fi
    ;;
  setenable)
    case "$2" in 1|0) setval SCHED_ENABLE "$2";; *) echo "ERR enable 0/1"; exit 1;; esac
    ;;
  setmode)
    case "$2" in pin|swipe|pattern) setval UNLOCK_MODE "$2";; *) echo "ERR mode pin|swipe|pattern"; exit 1;; esac
    ;;
  setopen)
    case "$2" in monkey|am) setval OPEN_MODE "$2";; *) echo "ERR open monkey|am"; exit 1;; esac
    ;;
  setsleep)
    case "$2" in 1|0) setval SLEEP_AFTER "$2";; *) echo "ERR sleep 0/1"; exit 1;; esac
    ;;
  setwatch)
    case "$2" in 1|0) setval WATCH_OPEN "$2";; *) echo "ERR watch 0/1"; exit 1;; esac
    ;;
  setcleanup)
    case "$2" in 1|0) setval CLEANUP_AFTER "$2";; *) echo "ERR cleanup 0/1"; exit 1;; esac
    ;;
  profiles)
    list_profiles
    ;;
  profile)
    SUB=$2
    case "$SUB" in
      add)
        # profile add SLUG NAME PKG [SCHED] [SCOPE]  (录制型新 profile; SCOPE=pkg|all)
        SLUG=$3; NAME=$4; PKG=$5; SCHED=$6; SCOPE=$7
        slugok "$SLUG" || { echo "ERR slug 仅字母数字_横线中文,<=24位"; exit 1; }
        nameok "$NAME" || { echo "ERR name 仅允许中文/字母数字/下划线/横线，<=32位"; exit 1; }
        pkgok "$PKG" || { echo "ERR pkg 仅允许字母数字下划线点，或留空"; exit 1; }
        # 录制方式: pkg=指定包名录取(核心路径, 原样保留) / all=全场录取(不绑定包名)
        case "$SCOPE" in
          ''|pkg) SCOPE=pkg;;
          all)    SCOPE=all; PKG=;;
          *)      echo "ERR scope pkg|all"; exit 1;;
        esac
        if [ -d $PFX/$SLUG ]; then echo "ERR profile $SLUG exists"; exit 1; fi
        if [ -n "$SCHED" ]; then
          case "$SCHED" in ''|*[!0-9]*) echo "ERR sched HHMM"; exit 1;; esac
          [ ${#SCHED} -ne 4 ] && { echo "ERR sched HHMM"; exit 1; }
          HH=${SCHED%??}; MM=${SCHED#??}
          if [ "$HH" -gt 23 ] || [ "$MM" -gt 59 ]; then echo "ERR sched HHMM"; exit 1; fi
        fi
        mkdir -p $PFX/$SLUG
        CT=$PFX/$SLUG/conf.tmp.$$
        if ! ( umask 077; {
          echo P_NAME=$NAME
          echo P_TYPE=record
          echo P_PKG=$PKG
          echo P_SCOPE=$SCOPE
          [ -n "$SCHED" ] && echo P_SCHED=$SCHED
        } > "$CT" ); then
          echo "ERR write profile"
          exit 1
        fi
        chmod 600 "$CT" 2>/dev/null
        if ! mv "$CT" "$PFX/$SLUG/conf" 2>/dev/null; then
          rm -f "$CT" 2>/dev/null
          echo "ERR write profile"
          exit 1
        fi
        echo "PROFILE_ADD $SLUG"
        ;;
      addicbc)
        # 恢复内置工行任务 (用户删掉后的一键找回)。
        # 必须先撤掉 no_icbc 标记: 只重建目录不撤标记的话, 下次开机 ensure_profiles
        # 会认为「用户要求不要它」而把它跳过, 恢复按钮就成了只成功一次的假动作。
        if [ -f $PFX/icbc/conf ]; then echo "ERR 内置工行任务已存在"; exit 1; fi
        rm -f "$NOICBC" 2>/dev/null
        mkdir -p $PFX/icbc 2>/dev/null || { echo "ERR mkdir icbc"; exit 1; }
        IST=$(sed -n 's/^SCHED_TIME=//p' "$CFG" 2>/dev/null | head -1)
        CT=$PFX/icbc/conf.tmp.$$
        if ! ( umask 077; {
          echo P_NAME=工行定时浇水
          echo P_TYPE=script
          echo P_PKG=com.icbc
          [ -n "$IST" ] && echo P_SCHED=$IST
        } > "$CT" ); then
          echo "ERR write icbc profile"
          exit 1
        fi
        chmod 600 "$CT" 2>/dev/null
        if ! mv "$CT" "$PFX/icbc/conf" 2>/dev/null; then
          rm -f "$CT" 2>/dev/null
          echo "ERR write icbc profile"
          exit 1
        fi
        echo "PROFILE_ADD icbc"
        ;;
      del)
        SLUG=$3
        slugok "$SLUG" || { echo "ERR slug"; exit 1; }
        [ -d $PFX/$SLUG ] || { echo "ERR no profile $SLUG"; exit 1; }
        # 内置工行任务也允许删 —— 别的用户不一定用得上它。删掉就立标记,
        # 否则 service.sh 每次开机 / customize.sh 每次安装都会把它重建回来。
        if [ "$SLUG" = "icbc" ]; then
          ( umask 077; : > "$NOICBC" ) 2>/dev/null || { echo "ERR write no_icbc"; exit 1; }
        fi
        rm -rf $PFX/$SLUG
        echo "PROFILE_DEL $SLUG"
        ;;
      set)
        # profile set SLUG KEY VALUE  KEY: p_name|p_pkg|p_sched|p_enable|p_cleanup|p_scale|p_days|p_scope|p_home
        SLUG=$3; KEY=$4; VAL=$5
        slugok "$SLUG" || { echo "ERR slug"; exit 1; }
        [ -f $PFX/$SLUG/conf ] || { echo "ERR no profile $SLUG"; exit 1; }
        case "$KEY" in
          p_name) KEY=P_NAME
            nameok "$VAL" || { echo "ERR name 禁空白/斜杠/壳元字符，且<=32位"; exit 1; }
            ;;
          p_pkg) KEY=P_PKG
            # 空值 = 清空 (亮屏即录)
            pkgok "$VAL" || { echo "ERR pkg 仅允许字母数字下划线点，或留空"; exit 1; }
            ;;
          p_days) KEY=P_DAYS
            # 空值 = 跟随全局 SCHED_DAYS; 0 = 该任务一周都不跑; 否则是升序 1-7 串
            daysok "$VAL" || { echo "ERR days 空=跟随全局, 0=不跑, 或 1-7 升序串如 135"; exit 1; }
            ;;
          p_scope) KEY=P_SCOPE
            # pkg = 指定包名录取(默认) / all = 全场录取(回放不绑定包名, 必须清空 P_PKG)
            case "$VAL" in
              pkg|all) ;;
              *) echo "ERR scope pkg|all"; exit 1;;
            esac
            ;;
          p_home) KEY=P_HOME
            # 回放前先回桌面; 只在无包名(全场录取/裸录)时生效, 默认 1
            case "$VAL" in 1|0) ;; *) echo "ERR home 0/1"; exit 1;; esac
            ;;
          p_sched) KEY=P_SCHED
            [ -n "$VAL" ] || { echo "ERR sched HHMM"; exit 1; }
            case "$VAL" in ''|*[!0-9]*) echo "ERR sched HHMM"; exit 1;; esac
            [ ${#VAL} -ne 4 ] && { echo "ERR sched HHMM"; exit 1; }
            HH=${VAL%??}; MM=${VAL#??}
            if [ "$HH" -gt 23 ] || [ "$MM" -gt 59 ]; then echo "ERR sched HHMM"; exit 1; fi
            ;;
          p_enable) KEY=P_ENABLE
            case "$VAL" in 1|0) ;; *) echo "ERR enable 0/1"; exit 1;; esac
            ;;
          p_cleanup) KEY=P_CLEANUP
            # 空值 = 跟随全局 CLEANUP_AFTER; 0 = 该任务不清; 1 = 该任务强制清
            case "$VAL" in
              1|0) ;;
              '') ;;
              *) echo "ERR cleanup 0/1"; exit 1;;
            esac
            ;;
          p_scale) KEY=P_SCALE
            # 0 = 不缩放(默认, 同机录制回放); 1 = 按录制时分辨率等比换算后再回放
            case "$VAL" in
              1|0) ;;
              *) echo "ERR scale 0/1"; exit 1;;
            esac
            ;;
          *) echo "ERR key p_name|p_pkg|p_sched|p_enable|p_cleanup|p_scale|p_days|p_scope|p_home"; exit 1;;
        esac
        if ! atomic_update "$PFX/$SLUG/conf" "$KEY" "$VAL"; then
          echo "ERR write profile"
          exit 1
        fi
        # 两个键互相牵制, 单写一个会让 profile 自相矛盾:
        #   p_scope=all 必须同时把包名清掉 —— 否则回放先去打开包名, 全场录的动作全错位;
        #   给了非空包名就必须退回 pkg 模式 —— 用户改填包名就是想走指定包名录取。
        if [ "$KEY" = "P_SCOPE" ] && [ "$VAL" = "all" ]; then
          if ! atomic_update "$PFX/$SLUG/conf" P_PKG ""; then
            echo "ERR clear P_PKG"
            exit 1
          fi
          echo "SET P_PKG="
        elif [ "$KEY" = "P_PKG" ] && [ -n "$VAL" ]; then
          CUR=$(sed -n 's/^P_SCOPE=//p' "$PFX/$SLUG/conf" 2>/dev/null | head -1)
          if [ "$CUR" = "all" ]; then
            atomic_update "$PFX/$SLUG/conf" P_SCOPE pkg || { echo "ERR write P_SCOPE"; exit 1; }
            echo "SET P_SCOPE=pkg"
          fi
        fi
        echo "SET $KEY=$VAL"
        ;;
      *) echo "ERR profile add|del|set"; exit 1;;
    esac
    ;;
  record)
    SUB=$2
    case "$SUB" in
      start)
        slugok "$3" || { echo "ERR slug"; exit 1; }
        [ -d $PFX/$3 ] || { echo "ERR no profile $3"; exit 1; }
        sh $REC start "$3"
        ;;
      stop)
        slugok "$3" || { echo "ERR slug"; exit 1; }
        sh $REC stop "$3"
        ;;
      status)
        sh $REC status
        ;;
      *) echo "ERR record start|stop|status"; exit 1;;
    esac
    ;;
  trigger)
    # 默认空=内置工行; 可指定 profile slug
    if [ -n "$2" ]; then
      slugok "$2" || { echo "ERR slug"; exit 1; }
      [ -d $PFX/$2 ] || { echo "ERR no profile $2"; exit 1; }
      # 录制型任务: 必须先录过动作才能跑, 否则直接提示 (避免白解锁开app空回放)
      PTYPE=$(sed -n 's/^P_TYPE=//p' $PFX/$2/conf 2>/dev/null)
      [ -z "$PTYPE" ] && PTYPE=script
      if [ "$PTYPE" != "script" ] && ! has_valid_actions "$PFX/$2/actions.rx"; then
        echo "ERR 任务还没有有效录制内容: 先点它卡片上的「开始录制」, 切到目标app操作, 再点「停止录制」生成动作, 之后才能跑"
        exit 1
      fi
      echo "$2" > $M/now.txt 2>/dev/null && echo "TRIGGERED $2" || { echo "ERR touch now.txt"; exit 1; }
    else
      # 默认空内容=内置工行；必须截断旧内容，不能用 touch 留下上次指定的任务名。
      : > $M/now.txt 2>/dev/null && echo "TRIGGERED" || { echo "ERR write now.txt"; exit 1; }
    fi
    ;;
  unlock)
    # 锁屏->解锁 往返测试 (校准图案宫格/PIN 键盘用): 由 service.sh 一次性处理。
    # 先确认守护在跑, 否则 unlock.txt 会一直没人消费, 界面只能干等到超时。
    pgrep -f "$M/service.sh" >/dev/null 2>&1 || { echo "ERR service not running"; exit 1; }
    rm -f $M/unlock.out 2>/dev/null
    echo 1 > $M/unlock.txt 2>/dev/null || { echo "ERR touch unlock.txt"; exit 1; }
    UWI=0
    while [ $UWI -lt 30 ]; do
      [ -f $M/unlock.out ] && break
      sleep 1
      UWI=$((UWI+1))
    done
    if [ -f $M/unlock.out ]; then
      URES=$(cat $M/unlock.out 2>/dev/null)
      rm -f $M/unlock.out $M/unlock.txt 2>/dev/null
      case "$URES" in
        UNLOCK_OK*) echo "UNLOCK_OK";;
        *) echo "ERR unlock failed (${URES:-no result})";;
      esac
    else
      rm -f $M/unlock.txt 2>/dev/null
      echo "ERR unlock test timed out"
    fi
    ;;
  restart)
    restart_svc
    ;;
  device)
    case "$2" in
      get)    dev_get;;
      set)    shift 2; dev_set "$@";;
      detect) dev_detect;;
      *)      echo "ERR device get|set|detect"; exit 1;;
    esac;;
  log)
    tail -60 $LOG 2>/dev/null || echo "(no log yet)"
    ;;
  *)
    echo "usage: webctl.sh status|setpin|setpattern|settime|setdays|setenable|setmode|setopen|setsleep|setwatch|setcleanup|unlock|trigger[NAME]|restart|log|profiles|profile add/addicbc/del/set|record start/stop/status|device get|set|detect"
    ;;
esac
exit 0