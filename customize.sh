#!/system/bin/sh
# icbc_daily_water 安装脚本 (KSU/Magisk customize.sh)
MODDIR=$(dirname "$0")
CFGDIR=/data/adb/icbc_water
CFG=$CFGDIR/sched.conf
PFX=$CFGDIR/profiles
WEB=$MODDIR/webroot

# 配置外置: 模块重刷/更新不丢 PIN 与时间设置
mkdir -p $CFGDIR 2>/dev/null
rm -f "$CFG".tmp.* "$CFG".pin.* 2>/dev/null
if [ ! -f $CFG ]; then
  cp $MODDIR/sched.conf $CFG 2>/dev/null || touch $CFG 2>/dev/null
fi
chmod 600 $CFG 2>/dev/null
chmod 755 $MODDIR/service.sh $MODDIR/water.sh $MODDIR/webctl.sh $MODDIR/record.sh $MODDIR/replay.sh 2>/dev/null

# 设备档案: 只在缺失时用模块内的模板初始化一次。
# 关键: 已存在的 device.conf 绝不覆盖 —— 用户在 WebUI 里选好的机型不能在升级时丢。
# 模板里 DEV_APPLY=0, 即保持 Xiaomi 17 Pro 的实测基线, 各脚本不读 DEV_* 覆盖项。
DEVCFG=$CFGDIR/device.conf
if [ ! -f $DEVCFG ]; then
  cp $MODDIR/device.conf $DEVCFG 2>/dev/null || {
    printf 'DEV_APPLY=0\nDEV_MODEL=17pro\nDEV_STATUS=stable\n' > $DEVCFG 2>/dev/null
  }
  echo "- 设备档案已初始化 (DEV_APPLY=0, 17 Pro 基线)"
else
  echo "- 设备档案已存在, 保持不变 (DEV_APPLY=$(grep -m1 '^DEV_APPLY=' $DEVCFG 2>/dev/null | cut -d= -f2))"
fi
chmod 600 $DEVCFG 2>/dev/null

# Profiles 目录 + 内置工行脚本型 profile (防重装后丢失)
# 例外: 用户在 WebUI 里删掉内置工行任务后会留下 no_icbc 标记, 那次删除是明确意愿,
# 升级/重刷不得把它又装回来 —— 否则"能删掉"就是假的。标记不删, 这里一个字节都不写。
mkdir -p $PFX 2>/dev/null
if [ ! -f $CFGDIR/no_icbc ] && [ ! -f $PFX/icbc/conf ]; then
  mkdir -p $PFX/icbc 2>/dev/null
  {
    echo P_NAME=工行定时浇水
    echo P_TYPE=script
    echo P_PKG=com.icbc
    echo P_SCHED=$(grep -m1 '^SCHED_TIME=' $CFG 2>/dev/null | cut -d= -f2)
  } > $PFX/icbc/conf 2>/dev/null
fi
if [ -f $CFGDIR/no_icbc ]; then
  echo "- 已按用户设置跳过内置工行任务 (no_icbc 标记存在)"
fi

# ---------- WebUI 完整性校验 ----------
# 升级后 WebUI 不更新的多半原因是 webroot 缺文件或权限不对(KSU WebView 读不到)。
# 这里逐个确认必需文件存在, 缺任何一个都要在安装日志里明确报错, 不能静默装完。
WEBERR=0
for f in index.html app.js i18n.js kernelsu.js; do
  if [ ! -f "$WEB/$f" ]; then
    echo "! webroot 缺少 $f —— WebUI 可能无法正常显示"
    WEBERR=1
  fi
done
if [ "$WEBERR" = "0" ]; then
  # 统一成 644: KSU WebView 以非 root 之外的身份读取, 权限过紧会白屏。
  chmod 644 "$WEB"/*.js "$WEB"/*.html 2>/dev/null
  chmod 755 "$WEB" 2>/dev/null
  # 清掉可能残留的临时文件, 避免旧缓存干扰。
  rm -f "$WEB"/*.tmp "$WEB"/*~ "$WEB"/.DS_Store 2>/dev/null
  echo "- WebUI 资源就绪 (共 $(ls -1 "$WEB" 2>/dev/null | wc -l) 个文件)"
else
  echo "! WebUI 资源不完整, 建议卸载后重新刷入本包"
fi

exit 0
