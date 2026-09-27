#!/usr/bin/env bash
# build_zip.sh - 从仓库内容重新生成可刷入的 KSU/Magisk 模块 zip
# 用法: bash tools/build_zip.sh   (在仓库根目录执行)
# 产物: ../xiaomi-17-pro-automation-v<版本>.zip
set -e

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VER=$(grep -m1 '^version=' "$ROOT/module.prop" | cut -d= -f2)
VC=$(grep -m1 '^versionCode=' "$ROOT/module.prop" | cut -d= -f2)
OUT="$(dirname "$ROOT")/xiaomi-17-pro-automation-${VER}.zip"
STAGE="${TMPDIR:-/tmp}/xiaomi_17_pro_automation_zip_stage.$$"
trap 'rm -rf "$STAGE"' EXIT HUP INT TERM

# 缓存击穿用的标记: 只含版本号与数字, 不含路径, 注入后校验一次替换确实发生。
CACHE_TAG="v${VC}"

rm -f "$OUT"
mkdir -p "$STAGE/tools" "$STAGE/webroot"
cp "$ROOT"/module.prop "$ROOT"/service.sh "$ROOT"/water.sh "$ROOT"/record.sh "$ROOT"/replay.sh \
   "$ROOT"/webctl.sh "$ROOT"/sched.conf "$ROOT"/device.conf "$ROOT"/customize.sh \
   "$ROOT"/README.md "$ROOT"/README.en.md "$ROOT"/README.fr.md \
   "$ROOT"/LICENSE "$ROOT"/.gitignore "$STAGE/"
cp "$ROOT"/webroot/* "$STAGE/webroot/"
cp "$ROOT"/tools/px.py "$ROOT"/tools/run_once.sh "$STAGE/tools/"

# ---------- WebUI 资源带版本号 ----------
# 模块升级后 KSU WebView 经常命中旧的 app.js / i18n.js, 表现就是「WebUI 没更新」。
# 给入口脚本和内部 import 加上 ?v=版本号, 让每个版本走不同的 URL, 绕过 WebView 缓存。
# 只在打包目录里改, 仓库源码保持干净可读。
# 注意1: 匹配串里不要写 \> 之类的组合 —— GNU sed 会当成词边界, 静默匹配失败。
# 注意2: import 语句末尾的 ' 必须写进「被匹配掉」的部分, 由替换串重新补一个,
#        否则 ?v= 会落到引号外面, 生成 from './x.js?v910''; 这种坏 JS。
sed -i \
  -e "s#\(src=\"\./app\.js\)#\1?${CACHE_TAG}#" \
  -e "s#\(from '\./kernelsu\.js\)'#\1?${CACHE_TAG}'#" \
  -e "s#\(from '\./i18n\.js\)'#\1?${CACHE_TAG}'#" \
  "$STAGE/webroot/index.html" "$STAGE/webroot/app.js"

# 注入失败必须让构建失败, 否则会悄悄发布一个「有缓存 bug 的包」。
grep -qF "src=\"./app.js?${CACHE_TAG}\"" "$STAGE/webroot/index.html" || {
  echo "构建失败: index.html 的 app.js 版本标记注入未生效" >&2; exit 1; }
# 行尾锚定: 这一行必须恰好是 import ... from './xxx.js?vNNN';
# 只做子串匹配会在 ?v 落到引号外(如 './xxx.js?vNNN'') 时误判通过。
grep -qE "^import .* from '\./kernelsu\.js\?${CACHE_TAG}';$" "$STAGE/webroot/app.js" || {
  echo "构建失败: app.js 的 kernelsu.js 版本标记注入未生效" >&2; exit 1; }
grep -qE "^import .* from '\./i18n\.js\?${CACHE_TAG}';$" "$STAGE/webroot/app.js" || {
  echo "构建失败: app.js 的 i18n.js 版本标记注入未生效" >&2; exit 1; }
# 反向检查: 打包产物里不允许残留重复引号或多次标记。
if grep -qE "\?${CACHE_TAG}'{2}|\?${CACHE_TAG}[^'\"]|\?${CACHE_TAG}\?${CACHE_TAG}" "$STAGE/webroot/app.js" "$STAGE/webroot/index.html"; then
  echo "构建失败: WebUI 资源里出现异常的版本标记" >&2; exit 1; fi

# WebUI 必需资源齐全才允许打包。
for f in index.html app.js i18n.js kernelsu.js; do
  [ -f "$STAGE/webroot/$f" ] || { echo "构建失败: webroot/$f 缺失" >&2; exit 1; }
done

chmod 755 "$STAGE"/service.sh "$STAGE"/water.sh "$STAGE"/record.sh "$STAGE"/replay.sh \
  "$STAGE"/webctl.sh "$STAGE"/customize.sh "$STAGE"/tools/run_once.sh
chmod 644 "$STAGE"/module.prop "$STAGE"/sched.conf "$STAGE"/device.conf \
  "$STAGE"/README.md "$STAGE"/README.en.md "$STAGE"/README.fr.md "$STAGE"/LICENSE \
  "$STAGE"/.gitignore "$STAGE"/tools/px.py "$STAGE"/webroot/*

(cd "$STAGE" && zip -qr "$OUT" .)

# ---------- 产物自检 ----------
# 少一个文件, 装上去就要么白屏、要么设备档案初始化不出来, 所以在这里拦住。
for f in module.prop service.sh water.sh record.sh replay.sh webctl.sh \
         sched.conf device.conf customize.sh \
         README.md README.en.md README.fr.md \
         webroot/index.html webroot/app.js webroot/i18n.js webroot/kernelsu.js; do
  unzip -l "$OUT" | grep -qF " $f" || { echo "构建失败: 产物缺少 $f" >&2; exit 1; }
done
# 设备档案模板必须是「不覆盖」状态: 装了包的新用户不该一上来就被别的机型参数接管。
grep -qE '^DEV_APPLY=0$' "$STAGE/device.conf" || {
  echo "构建失败: device.conf 模板的 DEV_APPLY 必须是 0(17 Pro 基线)" >&2; exit 1; }
# 明文 PIN / 密钥不得出现在包内任何文件
if grep -rIlE '(api[_-]?key|secret[_-]?key|bearer +[A-Za-z0-9]|BEGIN +RSA)' "$STAGE" 2>/dev/null | grep -q .; then
  echo "构建失败: 产物里出现疑似密钥" >&2; exit 1
fi

echo "已生成: $OUT"
echo "WebUI 缓存标记: $CACHE_TAG"
