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
   "$ROOT"/README.md "$ROOT"/README.en.md "$ROOT"/README.fr.md "$ROOT"/README.ru.md \
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

# ---------- 文档缓存自愈标记 ----------
# ?v= 只能救子资源; 文档(index.html)本身被 WebView 缓存时, 新版本根本到不了。
# 这里把 versionCode 注入 app.js 的 BUILD_VC 占位符: 运行时它拿设备上模块的
# versionCode 对比, 不一致就强制换 URL 重拉文档(见 app.js 的 selfHeal)。
grep -qF "const BUILD_VC = '__BUILD_VC__';" "$ROOT/webroot/app.js" || {
  echo "构建失败: app.js 缺少 __BUILD_VC__ 占位符, WebUI 缓存自愈会失效" >&2; exit 1; }
grep -qF "const BUILD_VER = '__BUILD_VER__';" "$ROOT/webroot/app.js" || {
  echo "构建失败: app.js 缺少 __BUILD_VER__ 占位符, WebUI 缓存自愈会失效" >&2; exit 1; }
# 只替换「声明那两行」, 不是全局替换。
# 全局替换会把 app.js 里其它以占位符为判据的代码一起改掉 —— 本仓库已经踩过一次:
# 自愈开关原本写成 if (BUILD_VC === '__BUILD_VC__') return;, 打包后变成
# if (BUILD_VC === '1120') return;, 恒为真, 产物里的自愈成了死代码。
# 锚定 + 后续的「判据必须原样保留」校验, 保证占位符只在声明行被消化。
sed -i \
  -e "0,/^const BUILD_VC = '__BUILD_VC__';$/s##const BUILD_VC = '${VC}';#" \
  -e "0,/^const BUILD_VER = '__BUILD_VER__';$/s##const BUILD_VER = '${VER}';#" \
  "$STAGE/webroot/app.js"
grep -qE "^const BUILD_VC = '${VC}';$" "$STAGE/webroot/app.js" || {
  echo "构建失败: app.js 的 BUILD_VC 注入未生效" >&2; exit 1; }
grep -qE "^const BUILD_VER = '${VER}';$" "$STAGE/webroot/app.js" || {
  echo "构建失败: app.js 的 BUILD_VER 注入未生效" >&2; exit 1; }
# 除声明行外不允许再有裸占位符: app.js 里的「源码态」判据必须原样保留
n_left=$(grep -c '__BUILD_VC__' "$STAGE/webroot/app.js" || true)
[ "$n_left" = "0" ] || {
  echo "构建失败: app.js 注入后仍有 $n_left 处 __BUILD_VC__, 自愈开关可能被一并改掉" >&2; exit 1; }
n_left=$(grep -c '__BUILD_VER__' "$STAGE/webroot/app.js" || true)
[ "$n_left" = "0" ] || {
  echo "构建失败: app.js 注入后仍有 $n_left 处 __BUILD_VER__, 自愈开关可能被一并改掉" >&2; exit 1; }
grep -qF "if (!/^\d+\$/.test(BUILD_VC) || BUILD_VER.charAt(0) !== 'v') return;" "$STAGE/webroot/app.js" || {
  echo "构建失败: app.js 的「源码态」判据被改坏, 产物里自愈会直接 return" >&2; exit 1; }
# 其它 webroot 文件不该出现占位符
if grep -rq '__BUILD_VC__\|__BUILD_VER__' "$STAGE/webroot" 2>/dev/null; then
  echo "构建失败: webroot 里残留构建期占位符" >&2; exit 1; fi

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
  "$STAGE"/README.md "$STAGE"/README.en.md "$STAGE"/README.fr.md "$STAGE"/README.ru.md \
  "$STAGE"/LICENSE \
  "$STAGE"/.gitignore "$STAGE"/tools/px.py "$STAGE"/webroot/*

(cd "$STAGE" && zip -qr "$OUT" .)

# ---------- 产物自检 ----------
# 少一个文件, 装上去就要么白屏、要么设备档案初始化不出来, 所以在这里拦住。
for f in module.prop service.sh water.sh record.sh replay.sh webctl.sh \
         sched.conf device.conf customize.sh \
         README.md README.en.md README.fr.md README.ru.md \
         webroot/index.html webroot/app.js webroot/i18n.js webroot/kernelsu.js; do
  unzip -l "$OUT" | grep -qF " $f" || { echo "构建失败: 产物缺少 $f" >&2; exit 1; }
done
# 设备档案模板必须是「不覆盖」状态: 装了包的新用户不该一上来就被别的机型参数接管。
grep -qE '^DEV_APPLY=0$' "$STAGE/device.conf" || {
  echo "构建失败: device.conf 模板的 DEV_APPLY 必须是 0(17 Pro 基线)" >&2; exit 1; }
# ---------- module.prop 自检 ----------
# description 是单行属性(readProperty 按第一个 = 切开、且不处理转义), 写多行
# 会被后面的行当成新键丢掉。这里把「中文优先、再英文」钉成断言。
# 注意别用 grep '[一-鿿]' 这类字符类: Termux 下 LANG 常常是空的, 它会退化成
# 逐字节匹配; wc -m 也会退化成 wc -c。改成按字面量标识串判断, 与 locale 无关。
n_desc=$(grep -c '^description=' "$STAGE/module.prop")
[ "$n_desc" = "1" ] || { echo "构建失败: module.prop 里 description 必须恰好一行" >&2; exit 1; }
DESC=$(sed -n 's/^description=//p' "$STAGE/module.prop")
[ -n "$DESC" ] || { echo "构建失败: module.prop 的 description 为空" >&2; exit 1; }
case "$DESC" in
  *" | "*) : ;;
  *) echo "构建失败: description 缺 ' | ' 分隔符(应为 中文段 | 英文段)" >&2; exit 1 ;;
esac
# 「中文优先」= 中文段在分隔符之前, 英文段在之后。两段各自都得是真内容,
# 不能把英文段塞到前面、或者让其中一段退化成空壳。
ZH_PART=${DESC%%" | "*}
EN_PART=${DESC#*" | "}
zh_ok=0; for m in 自动化模块 定时 录制 回放 浇水; do
  case "$ZH_PART" in *"$m"*) zh_ok=1 ;; esac
done
[ "$zh_ok" = 1 ] || { echo "构建失败: description 的中文段里找不到中文标识串" >&2; exit 1; }
en_ok=0; for m in automation scheduler record replay WebUI; do
  case "$EN_PART" in *"$m"*) en_ok=1 ;; esac
done
[ "$en_ok" = 1 ] || { echo "构建失败: description 的英文段里找不到英文标识串" >&2; exit 1; }
# 模块列表里 description 会被折行/截断, 太长等于没写。LANG 为空时 wc -m == wc -c,
# 所以这里就用字节数, 阈值按「中英两段都留得住」定。
dlen=$(printf '%s' "$DESC" | wc -c)
[ "$dlen" -le 1100 ] || {
  echo "构建失败: module.prop 的 description 太长($dlen 字节, 列表里会被截断)" >&2; exit 1; }
# 明文 PIN / 密钥不得出现在包内任何文件
if grep -rIlE '(api[_-]?key|secret[_-]?key|bearer +[A-Za-z0-9]|BEGIN +RSA)' "$STAGE" 2>/dev/null | grep -q .; then
  echo "构建失败: 产物里出现疑似密钥" >&2; exit 1
fi

# 四份 README 必须都在, 且顶部互链齐全(少一种语言, 用户就找不到自己的文档)
for pair in "README.md:README.en.md README.fr.md README.ru.md" \
            "README.en.md:README.md README.fr.md README.ru.md" \
            "README.fr.md:README.md README.en.md README.ru.md" \
            "README.ru.md:README.md README.en.md README.fr.md"; do
  src=${pair%%:*}
  for other in ${pair#*:}; do
    grep -qF "$other" "$STAGE/$src" || { echo "构建失败: $src 缺少指向 $other 的链接" >&2; exit 1; }
  done
done

# ---------- README 里的 webctl.sh 示例必须真的能跑 ----------
# 文档里写错的命令比没有文档更糟: 用户照抄就失败。四份 README 都会给出
# webctl.sh 的命令行示例(Magisk / APatch 下没有 WebUI, 只能这么配), 所以
# 在产物上逐份核对。注意要「逐份」而不是把四份合起来看一次 —— 合并会让其中
# 一份丢了示例也照样通过, 翻译就悄悄退化成不给 Magisk 用户留路了。
DOCS="README.md README.en.md README.fr.md README.ru.md"
for src in $DOCS; do
  subs=$(grep -hoE 'webctl\.sh [a-z]+' "$STAGE/$src" | awk '{print $2}' | sort -u)
  [ -n "$subs" ] || {
    echo "构建失败: $src 里没有 webctl.sh 用法示例(与 Magisk 兼容性说明不一致)" >&2; exit 1; }
  for s in $subs; do
    grep -qE "^  $s\)" "$STAGE/webctl.sh" || {
      echo "构建失败: $src 用了 webctl.sh $s, 但 webctl.sh 里没有这个子命令" >&2; exit 1; }
  done
  # setpin 只认 WEBUI_PIN 环境通道(webctl.sh 里 V=\$WEBUI_PIN), 写成 setpin 123456
  # 必然失败, 而且明文 PIN 会进进程列表 —— 两条都不能出现在文档里。
  if grep -qE 'webctl\.sh setpin +[0-9]' "$STAGE/$src"; then
    echo "构建失败: $src 里 setpin 带了位置参数(必须走 WEBUI_PIN 环境变量)" >&2; exit 1
  fi
  # settime 是唯一带取值的示例子命令, 只收 4 位 HHMM 且 HH<=23 / MM<=59
  # (webctl.sh 里就是这两条范围检查, 越界直接 ERR invalid HHMM)。
  if grep -oE "webctl\.sh settime +[^' ]+" "$STAGE/$src" \
       | grep -qvE 'settime +(0[0-9]|1[0-9]|2[0-3])([0-5][0-9])$'; then
    echo "构建失败: $src 里 webctl.sh settime 的参数不是合法的 4 位 HHMM" >&2; exit 1
  fi
  # 说清 WebUI 只在 KernelSU 下可用 —— Magisk / APatch 用户直接看这张表
  grep -qF 'kernelsu.js' "$STAGE/$src" || {
    echo "构建失败: $src 的运行环境说明里没提 kernelsu.js 依赖" >&2; exit 1; }
done
# Magisk-Modules-Alt-Repo 等第三方模块仓库要求「README.md 是英文的」。我们的
# README.md 以中文为主(用户明确要求), 所以顶部保留一段英文概览来满足这条,
# 中文正文依然是主文档。别把这段删掉, 否则投第三方仓库会被直接退回。
grep -qF '**English summary**' "$STAGE/README.md" || {
  echo "构建失败: README.md 缺少顶部英文概览(第三方模块仓库要求 README.md 含英文)" >&2; exit 1; }
grep -qF '**License:** MIT' "$STAGE/README.md" || {
  echo "构建失败: README.md 英文概览里没写 License(第三方仓库要求明确可再分发)" >&2; exit 1; }

echo "已生成: $OUT"
echo "WebUI 缓存标记: $CACHE_TAG (BUILD_VC=$VC)"
