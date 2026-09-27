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

# Profiles 目录 + 内置工行脚本型 profile (防重装后丢失)
mkdir -p $PFX 2>/dev/null
if [ ! -f $PFX/icbc/conf ]; then
  mkdir -p $PFX/icbc 2>/dev/null
  {
    echo P_NAME=工行定时浇水
    echo P_TYPE=script
    echo P_PKG=com.icbc
    echo P_SCHED=$(grep -m1 '^SCHED_TIME=' $CFG 2>/dev/null | cut -d= -f2)
  } > $PFX/icbc/conf 2>/dev/null
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
