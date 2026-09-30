#!/system/bin/sh
# icbc_daily_water / water.sh v7.7  前台门: 工行不到前台绝不动手 + 耐心找首页
# 纯 root 直控: screencap 取屏 + 像素探针判定 + sendevent 注入, 不用无障碍/Xposed/input
echo VER v7.7

# ============ 设备配置区 (每台设备按 README 校准) ============
D=4630946949513469331        # 显示ID: dumpsys display 查, 多数手机为 0
SW=1220                      # 屏幕宽(像素)
SH=2656                      # 屏幕高(像素)
WORK=/sdcard/Download        # 截图/取证输出目录
SNAP=0                       # 0=默认: 不生成过程取证图, 跑完自动清理 (快, 也不会往你相册里堆图)
                             # 1=排查模式: 全程留取证图且跳过清理
CHOWN=10278:1023             # 取证文件属主 (留空=不 chown)
# ============================================================

# ---- 设备档案覆盖 (v0.11.0 新增, opt-in) ----
# device.conf 的 DEV_APPLY=0 时(默认值, 也是 Xiaomi 17 Pro 走的路径), 本段完全不执行,
# 上面 D/SW/SH 三个值就是最终值, 与 v0.10.0 逐字节一致。
# 只有显式设成 1 才用 DEV_* 覆盖, 且每个值都先做「唯一 + 纯数字 + 合理下限」校验:
# 不合格就保留原值。这样即使 device.conf 损坏或被截断, 后果也只是覆盖不生效, 不会把流程带歪。
# 重复键视为歧义配置: 取 head -1 会让「后面追加一行」悄悄改掉生效值, 不接受这种写法。
DEVCONF=/data/adb/icbc_water/device.conf
devpick() {  # devpick KEY -> 纯数字值; 缺失/重复/非纯数字一律返回空, 由调用方保留原值
  [ -f "$DEVCONF" ] || return 0
  [ "$(grep -c "^$1=" "$DEVCONF" 2>/dev/null)" = "1" ] || return 0
  sed -n "s/^$1=\([0-9][0-9]*\)$/\1/p" "$DEVCONF" 2>/dev/null | head -1
}
# 总闸同样要求「DEV_APPLY 只出现一次且值为 1」, 否则整体不覆盖。
if [ "$(grep -c '^DEV_APPLY=' "$DEVCONF" 2>/dev/null)" = "1" ] \
   && [ "$(sed -n 's/^DEV_APPLY=\(1\)$/1/p' "$DEVCONF" 2>/dev/null | head -1)" = "1" ]; then
  DV_SW=$(devpick DEV_SW)
  DV_SH=$(devpick DEV_SH)
  DV_D=$(devpick DEV_D)
  # 屏宽/屏高给个下限: 0 或个位数会让像素偏移算到负数, 直接判为非法。
  # 显示 ID 允许 0(多数手机就是 0), 所以只查非空。
  if [ -n "$DV_SW" ] && [ "$DV_SW" -ge 300 ] 2>/dev/null; then SW=$DV_SW; fi
  if [ -n "$DV_SH" ] && [ "$DV_SH" -ge 300 ] 2>/dev/null; then SH=$DV_SH; fi
  if [ -n "$DV_D" ]; then D=$DV_D; fi
  echo DEV_PROFILE APPLY=1 SW=$SW SH=$SH D=$D
fi

RAW=$WORK/zxr.raw
M=/data/adb/modules/icbc_daily_water

# ---- 内容区哈希的对齐参数 ----
# 页面稳定检测要反复对「y300~y2300 这片内容区」求 md5。旧写法是
#   dd bs=1 skip=1464012 count=9760000
# bs=1 意味着 976 万次 1 字节 read(), 实测单轮 5.16 秒, 而这个循环最多跑 8 轮 ——
# 单是「判断页面有没有加载完」就要 40 多秒, 这就是「往下翻太慢」的元凶。
# 改成 4096 对齐的大块读: 同样一片区域, 单轮 0.01 秒 (实测 516 倍)。
# 两个数都向上取整到 bs 的整数倍, 于是 skip/count 的单位就是「块」, 不需要 GNU 的
# iflag=skip_bytes 扩展 —— toybox / BusyBox / coreutils 的 dd 都认这种写法。
# 向上取整(而不是向下)是刻意的: 起点不早于 y300, 保证状态栏时钟的变化不会把
# 「页面已稳定」这个判断搅黄 —— 那正是原文注释里特意要避开时钟的原因。
HBS=4096
HSK=$(( (12 + 300 * SW * 4 + HBS - 1) / HBS ))
HCT=$(( (2000 * SW * 4 + HBS - 1) / HBS ))

# ---- 收尾清理 ----
# 以前全脚本一个 rm 都没有, 于是每次跑完都往 /sdcard/Download 里留一堆东西:
#   zxr.raw       12.36 MB 的原始帧, 永远不会被删
#   zx_*.png      全屏取证图, 相册里看得见
# 现在按「这张图还有没有用」决定去向:
#   zxr.raw       任何情况都删 —— 下一次运行会重新生成, 留着纯占空间
#   *_fail.png    只在失败时保留 —— 「为什么没浇水」只有这两张图说得清
#   其余 zx_*.png 一律删
# SNAP=1 是排查模式, 整段跳过, 全套留着给人看。
# KEEP_FAIL 由各失败分支在退出前置上, 成功路径不置。
KEEP_FAIL=0
cleanup_files() {
  [ "$SNAP" = "1" ] && return 0
  rm -f "$RAW" 2>/dev/null
  if [ "$KEEP_FAIL" = "1" ]; then
    for f in "$WORK"/zx_*.png; do
      case "$f" in
        *_fail.png) : ;;
        *) rm -f "$f" 2>/dev/null ;;
      esac
    done
  else
    rm -f "$WORK"/zx_*.png 2>/dev/null
  fi
}

L=$M/lock
mkdir $L 2>/dev/null || exit 9
trap 'cleanup_files; rmdir $L 2>/dev/null' 0 1 2 15

# ================= 设备发现 (单遍扫描 + boot_id 缓存) =================
discdev() {
  TDEV=; BDEV=; PDEV=
  for e in /dev/input/event*; do
    P=$(getevent -p $e 2>/dev/null)
    case "$P" in *Xiaomi_Touch_Input_0*) [ -z "$TDEV" ] && TDEV=$e;; esac
    case "$P" in *'009e'*) [ -z "$BDEV" ] && BDEV=$e;; esac
    case "$P" in *'0074'*) [ -z "$PDEV" ] && PDEV=$e;; esac
  done
  [ -z "$TDEV" ] && TDEV=/dev/input/event8
}
BID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
if [ -f $M/dev.conf ] && grep -q "BID=$BID" $M/dev.conf 2>/dev/null; then
  . $M/dev.conf 2>/dev/null
fi
if [ -z "$TDEV" ] || [ ! -e "$TDEV" ]; then
  discdev
  { echo "BID=$BID"; echo "TDEV=$TDEV"; echo "BDEV=$BDEV"; echo "PDEV=$PDEV"; } > $M/dev.conf 2>/dev/null
fi
echo DEVT TDEV=$TDEV BDEV=$BDEV PDEV=$PDEV

# ---- 0. 工行前台门: 工行不到前台绝不动手 (防误按其它 App) ----
FGOK=0
i=0
while [ $i -lt 30 ]; do
  FG=$(dumpsys activity activities 2>/dev/null | grep -m1 topResumedActivity)
  [ -z "$FG" ] && FG=$(dumpsys activity activities 2>/dev/null | grep -m1 -E 'mResumedActivity|mFocusedActivity')
  case "$FG" in
    *"com.icbc"*) FGOK=1; break;;
  esac
  [ $i -eq 0 ] && echo S0_WAIT_FG
  sleep 2
  i=$((i+1))
done
echo "S0_FG FGOK=$FGOK"
if [ $FGOK -eq 0 ]; then
  echo FG_FAIL
  buzz
  echo FAIL_END 3
  exit 3
fi

# ================= 注入原语 =================
stap() {
  sendevent $TDEV 3 47 0
  sendevent $TDEV 3 57 1
  sendevent $TDEV 3 53 $(( $1 * 100 ))
  sendevent $TDEV 3 54 $(( $2 * 100 ))
  sendevent $TDEV 3 48 20
  sendevent $TDEV 3 49 20
  sendevent $TDEV 1 330 1
  sendevent $TDEV 0 0 0
  sleep 0.08
  sendevent $TDEV 3 57 -1
  sendevent $TDEV 1 330 0
  sendevent $TDEV 0 0 0
}

sswipe() {
  sendevent $TDEV 3 47 0
  sendevent $TDEV 3 57 1
  sendevent $TDEV 3 53 $(( $1 * 100 ))
  sendevent $TDEV 3 54 $(( $2 * 100 ))
  sendevent $TDEV 3 48 20
  sendevent $TDEV 1 330 1
  sendevent $TDEV 0 0 0
  i=0
  while [ $i -le 10 ]; do
    sendevent $TDEV 3 53 $(( ( $1 + ($3 - $1) * i / 10 ) * 100 ))
    sendevent $TDEV 3 54 $(( ( $2 + ($4 - $2) * i / 10 ) * 100 ))
    sendevent $TDEV 0 0 0
    i=$((i+1))
  done
  sleep 0.1
  sendevent $TDEV 3 57 -1
  sendevent $TDEV 1 330 0
  sendevent $TDEV 0 0 0
}

sback() {
  [ -z "$BDEV" ] && return 1
  sendevent $BDEV 1 158 1
  sendevent $BDEV 0 0 0
  sleep 0.05
  sendevent $BDEV 1 158 0
  sendevent $BDEV 0 0 0
}

# ================= 截图/探针 =================
shot() {
  screencap -d $D $RAW
  echo "SHOT rc=$? sz=$(wc -c < $RAW 2>/dev/null)"
}
snap() {  # snap <tag>  取证留档 (SNAP=0 时跳过)
  [ "$SNAP" = "1" ] || return 0
  screencap -d $D -p $WORK/zx_v75_$1.png 2>/dev/null
  RCN=$?
  [ -n "$CHOWN" ] && chown $CHOWN $WORK/zx_v75_$1.png 2>/dev/null
  echo "SNAP $1 rc=$RCN"
}
PX() { set -- $(dd if=$RAW bs=1 skip=$((12+(($2*$SW+$1)*4))) count=3 2>/dev/null | od -An -tu1 -v); Rv=$1; Gv=$2; Bv=$3; }
DPX() { echo "DPX ($1,$2) RGB=$Rv,$Gv,$Bv"; }
ORANGE() { [ $Rv -gt 200 ] && [ $Gv -gt 90 ] && [ $Gv -lt 190 ] && [ $Bv -lt 140 ]; }
BLUE() { [ $Bv -gt 200 ] && [ $Rv -lt 170 ] && [ $Gv -gt 100 ] && [ $Gv -lt 220 ]; }

# ================= 自适应等待 =================
# 把「固定 sleep N 秒之后看一眼」换成「每 0.2 秒看一眼, 满足就立刻往下走, 到 N 秒为止」。
# 页面渲染普遍只要 0.5~1.5 秒, 而旧写法必须睡满 N 秒才算数 —— 这就是「进任务太慢」的来源。
#
# 超时用墙上时钟算, 上限就是原来的 N 秒, 所以页面一直不变时最坏也就多出「一轮截屏
# + 0.2 秒」的开销; 而常见情况下每处能省 1~2 秒。
hash_content() {  # 当前 $RAW 内容区(y300~y2300) 的 md5, 参数取自上面算好的 HBS/HSK/HCT
  dd if=$RAW bs=$HBS skip=$HSK count=$HCT 2>/dev/null | md5sum | cut -d' ' -f1
}

# wait_chg <旧哈希> <上限秒> —— 内容区发生变化(跳转/滚动)返回 0
# 两边任一为空都判为「没变化」: 哈希算不出来时宁可等满超时, 也不能当成就绪去点下一下。
wait_chg() {
  WC_OLD=$1
  WC_END=$(( $(date +%s) + $2 ))
  while :; do
    shot
    WC_NEW=$(hash_content)
    if [ -n "$WC_OLD" ] && [ -n "$WC_NEW" ] && [ "$WC_NEW" != "$WC_OLD" ]; then return 0; fi
    [ "$(date +%s)" -ge "$WC_END" ] && return 1
    sleep 0.2
  done
}

# wait_fn <上限秒> <判定函数> —— 每轮先 shot 再调 <判定函数>, 返回 0 即满足
wait_fn() {
  WF_END=$(( $(date +%s) + $1 ))
  WF_FN=$2
  while :; do
    shot
    "$WF_FN" && return 0
    [ "$(date +%s)" -ge "$WF_END" ] && return 1
    sleep 0.2
  done
}

# ---- 判定函数 (调用前 shot 已完成) ----
is_home() {          # 橙色卡行三点投票 ≥2 即工行首页
  PX 216 778; C1=0; ORANGE && C1=1
  PX 518 780; C2=0; ORANGE && C2=1
  PX 746 748; C3=0; ORANGE && C3=1
  V=$((C1+C2+C3))
  [ $V -ge 2 ]
}
is_water() {         # 浇水页确认点
  PX 750 746
  BLUE
}

# ================= 震动提示 (守护态可靠) =================
buzz() {
  for n in /sys/class/leds/vibrator/activate /sys/class/leds/vibrator/state /sys/class/leds/vibrator/transient; do
    if [ -w "$n" ]; then
      echo 1 > $n 2>/dev/null
      sleep 0.9
      echo 0 > $n 2>/dev/null
      echo "BUZZ $n rc=0"
      return 0
    fi
  done
  echo BUZZ no-node
  return 1
}

# ================= 屏幕状态 =================
W=0
dumpsys power 2>/dev/null | grep -q 'mWakefulness=Awake' && W=1
echo S0_WAKE W=$W
if [ $W -eq 0 ]; then
  if [ -n "$PDEV" ]; then
    sendevent $PDEV 1 116 1
    sendevent $PDEV 0 0 0
    sleep 0.05
    sendevent $PDEV 1 116 0
    sendevent $PDEV 0 0 0
  elif [ -n "$TDEV" ]; then
    sendevent $TDEV 1 143 1
    sendevent $TDEV 0 0 0
    sleep 0.05
    sendevent $TDEV 1 143 0
    sendevent $TDEV 0 0 0
  fi
  sleep 2
fi
svc power stayon true 2>/dev/null

# ---- 1. 回到工行首页: 橙色卡行三点投票 (≥2 即首页) ----
H=0
C1=0; C2=0; C3=0
if [ -n "$BDEV" ]; then
  i=0
  while [ $i -lt 6 ]; do
    shot
    PX 216 778; C1=0; ORANGE && C1=1; DPX 216 778
    PX 518 780; C2=0; ORANGE && C2=1; DPX 518 780
    PX 746 748; C3=0; ORANGE && C3=1; DPX 746 748
    V=$((C1+C2+C3))
    echo "VOTE=$V"
    if [ $V -ge 2 ]; then
      H=1
      echo S1_HOME
      snap home
      break
    fi
    # 耐心等待: 前 2 次探测不回退, 避免和冷启动/手动导航打架
    if [ $i -ge 2 ]; then
      sback
    fi
    sleep 2
    i=$((i+1))
  done
fi
if [ $H -ne 1 ]; then
  echo S1_MONKEY
  monkey -p com.icbc -c android.intent.category.LAUNCHER 1
  # 冷启动从 2 秒到十几秒都有: 固定睡 10 秒要么白等、要么还不够。改成每 0.2 秒
  # 探一次首页橙色卡行, 上限仍是 10 秒 —— 启动快的时候立刻往下走。
  wait_fn 10 is_home
  # wait_fn 返回时 $RAW 就是它最后一次截的屏, 不用再 shot; 这里只是照原样把三个
  # 探针点打到日志里(VOTE 是排查「卡在启动页」时唯一能看的东西)。
  PX 216 778; C1=0; ORANGE && C1=1; DPX 216 778
  PX 518 780; C2=0; ORANGE && C2=1; DPX 518 780
  PX 746 748; C3=0; ORANGE && C3=1; DPX 746 748
  V=$((C1+C2+C3))
  echo "VOTE=$V"
  [ $V -ge 2 ] && H=1
fi
if [ $H -ne 1 ]; then
  echo HOME_FAIL
  KEEP_FAIL=1            # 失败现场要留 —— 见 cleanup_files 的说明
  screencap -d $D -p $WORK/zx_home_fail.png 2>/dev/null
  [ -n "$CHOWN" ] && chown $CHOWN $WORK/zx_home_fail.png 2>/dev/null
  buzz
  echo FAIL_END 1
  exit 1
fi

# 首页已确认: 等热门任务等模块渲染完再探测/点击 (避免点到未加载页)。
# 判据是「内容区跟首页刚确认时不一样了」= 模块渲染出来了; 渲染完就立刻往下走。
# 页面本来就已经加载好的情况下会等满 2 秒, 与改动前的固定 sleep 2 一样, 不会更慢。
HOME_H=$(hash_content)
wait_chg "$HOME_H" 2

# ---- 2. 入口点击 + 广告快速防御 (复用 S1 的 RAW, 不再重截) ----
PX 1150 345
L0=$(((Rv+Gv+Bv)/3))
PX 600 1200
MX=$Rv; MN=$Rv
[ $Gv -gt $MX ] && MX=$Gv
[ $Gv -lt $MN ] && MN=$Gv
[ $Bv -gt $MX ] && MX=$Bv
[ $Bv -lt $MN ] && MN=$Bv
M0=$((MX-MN))
if [ $L0 -ge 160 ] && [ $M0 -le 70 ]; then
  echo S2_ENTRY
  # 「进任务」原来固定睡 3 秒。改成点之前先记一帧内容区, 点完盯着它变 ——
  # 页面一跳转就往下走, 通常 0.5~1.5 秒, 上限仍是 3 秒。
  ENTRY_H=$(hash_content)
  stap 606 1067
  wait_chg "$ENTRY_H" 3
  PX 1150 345
  L1=$(((Rv+Gv+Bv)/3))
  echo "S2_AFTER_ENTRY L=$L1"
  # 广告防御: 仅当页面又暗又变(和首页/任务页都不同)才快速点, 最多2次, 每次最多等2秒
  K=0
  while [ $K -lt 2 ]; do
    PX 1150 345; L1=$(((Rv+Gv+Bv)/3)); PX 750 750; WP_A=0; BLUE && WP_A=1
    if [ $L1 -lt 130 ] && [ $WP_A -eq 0 ]; then
      echo S2_ADQ
      AD_H=$(hash_content)
      stap 1144 326
      wait_chg "$AD_H" 2
      K=$((K+1))
    else
      break
    fi
  done
  snap s2_done
  PX 1150 345; DPX 1150 345
  PX 750 750; DPX 750 750
  PX 608 2138; DPX 608 2138
fi

# ---- 3. 下滑一屏 + 立即参与 ----
# 自适应等待: 网络慢时热门任务可能加载很久, 每轮对比内容区(y300-2300, 避开状态栏时钟),
# 两次相同=页面稳定再下滑; 最多 8 轮超时也照滑, 避免死等。
# 这里的 NK 走的是上面的 hash_content —— 4096 对齐大块读, 单轮 0.01 秒;
# 换成它之前是 `dd bs=1 count=9760000`, 976 万次 1 字节读, 单轮 5.16 秒,
# 8 轮最坏 40 多秒, 也就是「往下翻太慢」的全部来源。
echo S3_SWIPE
K=0
STABLE=0
CK=
while [ $K -lt 8 ]; do
  screencap -d $D $RAW
  NK=$(hash_content)
  if [ -n "$CK" ] && [ "$CK" = "$NK" ]; then
    STABLE=1
    echo "S3_SETTLED k=$K"
    break
  fi
  CK=$NK
  sleep 1
  K=$((K+1))
done
[ $STABLE -eq 1 ] || echo "S3_WAIT_TIMEOUT k=$K"
# 滑动前记一帧, 滑完盯着它变 —— 内容一动就算滑到位, 原来是固定睡 2 秒。
SWIPE_H=$(hash_content)
sswipe 610 1900 610 900
wait_chg "$SWIPE_H" 2
snap s3_swiped
PX 1150 345; DPX 1150 345
PX 750 750; DPX 750 750
PX 608 2138; DPX 608 2138
echo S3_TAP
TAP_H=$(hash_content)
stap 608 2138
wait_chg "$TAP_H" 3
snap s3_tapped
PX 1150 345; DPX 1150 345
PX 750 750; DPX 750 750
PX 608 2138; DPX 608 2138

# ---- 4. 浇水页确认 + 浇水 ----
# 第一次立刻判; 没看到浇水点再每 0.2 秒探一次, 上限 5 秒。
# 旧写法是「判一次 → 睡 5 秒 → 再判一次 → 还要再睡 5 秒」: 实际只有 t=0 和 t=5 两个
# 判定时刻, 而失败时最后那 5 秒纯属白睡, 全程要 10 秒。
# 新写法覆盖 [0,5] 区间上每 0.2 秒一个点 —— 覆盖范围只多不少, 失败却只要 5 秒。
WP=0
shot
PX 750 746
BLUE && WP=1
DPX 750 746
if [ $WP -ne 1 ] && wait_fn 5 is_water; then
  WP=1
  echo S4_RETRY_OK
  DPX 750 746
fi
snap s4
if [ $WP -eq 1 ]; then
  echo S4_WP
  stap 750 750
  # 这 2 秒是留给「点浇水」本身生效的, 不是等页面 —— 不能拿掉, 也不能改成轮询。
  sleep 2
  # 成功路径刻意不截图: 以前这里会写一张 zx_water.png, 紧接着又要删掉它,
  # 一张全屏 PNG 的编码纯属白做(取证截图在 SNAP=0 下本来就不生成)。
  echo WATER_OK
  buzz
  echo FAIL_END 0
  exit 0
else
  KEEP_FAIL=1            # 失败现场要留 —— 见 cleanup_files 的说明
  screencap -d $D -p $WORK/zx_water_fail.png 2>/dev/null
  [ -n "$CHOWN" ] && chown $CHOWN $WORK/zx_water_fail.png 2>/dev/null
  echo WATERPAGE_FAIL
  buzz
  echo FAIL_END 2
  exit 2
fi