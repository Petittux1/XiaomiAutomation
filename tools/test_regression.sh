#!/usr/bin/env bash
# test_regression.sh — 最小回归守卫
#
# 为什么是「断言式」而不是「跑一遍比输出」:
#   这套测试原本住在仓库外面(/tmp/opencode), 环境在 2026-09-27 ~ 09-30 之间切换时
#   整批丢失, 连事先录好的执行输出基线(v1010_*.out)也一起没了 —— 那类基线没法从
#   git 恢复, 因为它是「在某个沙箱里跑出来的结果」, 不是仓库内容。
#   所以这次改成把不变量直接写成断言: 不需要沙箱, 不需要预先录好的输出,
#   任何时候 clone 下来都能跑, 再丢一次也无所谓。
#
# 七条守卫各挡一类真实发生过/差一点发生的事故:
#   1) water.sh 的 17 Pro 基线取值 —— 防「顺手改坐标/阈值」把唯一实测过的机型改挂
#   2) service.sh 的单命中          —— 防同一天浇两次(重复触发是最恶劣的失败模式)
#   3) app.js 的 DOM 引用           —— 防删元素后白屏(删 card.time 时真的会踩到)
#   4) i18n 四语键集一致            —— 防只删/只加了一种语言的键
#   5) water.sh 的截图生命周期      —— 防取证图重新开始永久残留
#   6) 内容区 md5 的字节范围        —— 防「坐标没动但判定输入挪了位」(v0.12.8 踩过)
#   7) 设备档案的形态转换          —— 防保存按钮再次「点了没反应」(v0.12.9 踩过)
#      后端那段由 test_sandbox.sh 第 6 节覆盖, 这里只钉前端 —— 主故障在前端,
#      而沙箱跑不到 app.js, 少了这条就还是「六条全绿、按钮是死的」。
#
# 用法: bash tools/test_regression.sh          (在仓库根目录)
# 退出码: 0 = 全绿, 1 = 有守卫失败

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

FAILS=0
SEC_AT=0                    # 进入本节时的 FAILS 计数, 用来判断「这一节有没有新失败」
ok()   { printf '  ok   %s\n' "$*"; }
fail() { printf '  FAIL %s\n' "$*"; FAILS=$((FAILS+1)); }
sec()  { printf '\n[%s]\n' "$*"; SEC_AT=$FAILS; }
secdone() { [ "$FAILS" = "$SEC_AT" ] && ok "$*"; }

# grep -c 匹配不到时退出码是 1。测试脚本要把多条失败都报出来而不是遇到第一条就退出,
# 所以这里不设 set -e, 且所有 grep -c 一律 || true。
gc() { grep -cF -- "$1" "$2" 2>/dev/null || true; }


# ============ 1. water.sh 的 17 Pro 基线 ============
# Xiaomi 17 Pro 是唯一实测过的机型, 它的取值必须与 v0.10.0 一致。
#
# 注意这里比的是「取值集合」而不是「出现次数」: 加速重构会把同一组探针复用到新的
# 判定函数里(例如 is_home / is_water), 次数变了但取值一个没改 —— 那不是回归。
# 真正要防的两件事分别由两条断言各管一头:
#   - 老取值必须还在      -> 拦「把 606 1067 改成 606 1068」
#   - 不能出现新取值      -> 拦「顺手加一个没实测过的坐标」
sec "1. water.sh 17 Pro 基线 vs v0.10.0"

if ! git rev-parse -q --verify refs/tags/v0.10.0 >/dev/null 2>&1; then
  fail "找不到 v0.10.0 tag —— 基线无法比对(需要完整的 git 仓库, 不是解压的 zip)"
else
  OLD=$(git show v0.10.0:water.sh)

  # --- 坐标/点击原语: 比集合 ---
  # 注意别把 python 的退出码丢在命令替换里: N_COORD=$(python3 ...) 只拿到 stdout,
  # 它 sys.exit(1) 的状态必须另外取出来落到 fail 上 —— 否则上面印着 FAIL, 底下
  # 却报「全部通过」。反例测试第一轮就是被这条漏过去的。
  N_COORD=$(python3 - "$OLD" <<'PY'
import re, sys
old, new = sys.argv[1], open('water.sh', encoding='utf-8').read()

def calls(t):
    s = set()
    # 只取「带坐标的注入原语」。stap/sswipe 是点击与滑动, PX 是像素探针。
    # \bPX 刻意不匹配 DPX(DPX 只是把上一次探针结果打到日志, 不产生新取值)。
    for pat in (r'\bstap\s+\d+\s+\d+',
                r'\bsswipe\s+(?:\d+\s+){3}\d+',
                r'\bPX\s+\d+\s+\d+'):
        for m in re.finditer(pat, t):
            s.add(' '.join(m.group(0).split()))
    return s

oc, nc = calls(old), calls(new)
bad = 0
if oc - nc:
    print('  FAIL 老坐标取值丢失: %s' % ', '.join(sorted(oc - nc))); bad += 1
if nc - oc:
    print('  FAIL 出现了 v0.10.0 没有的坐标: %s' % ', '.join(sorted(nc - oc))); bad += 1
if not bad:
    print('  ok   %d 种坐标取值与 v0.10.0 完全一致(次序/次数不计)' % len(oc))
sys.exit(1 if bad else 0)
PY
)
  N_RC=$?
  [ -z "$N_COORD" ] || printf '%s\n' "$N_COORD"
  if [ "$N_RC" != "0" ]; then
    fail "坐标取值与 v0.10.0 不一致 (详见上方 FAIL 行)"
  elif [ -z "$N_COORD" ]; then
    fail "坐标比对脚本没输出任何东西 —— python3 heredoc 可能坏了"
  fi

  # --- 设备常量: 必须逐字节相同 (这三项是 DEV_APPLY=0 时的最终值) ---
  for p in 'D=4630946949513469331' 'SW=1220' 'SH=2656'; do
    a=$(printf '%s\n' "$OLD" | grep -cF -- "$p" || true)
    b=$(gc "$p" water.sh)
    if [ "$a" = "0" ]; then
      fail "基线常量在 v0.10.0 里就不存在: '$p' (守卫清单写错了?)"
    elif [ "$b" -lt 1 ] 2>/dev/null; then
      fail "water.sh 丢了设备常量 '$p' —— 17 Pro 基线被改动"
    fi
  done

  # --- 判定阈值: 只要还在, 就说明判定逻辑没被调过 ---
  for p in 'ORANGE()' 'BLUE()' \
           'Rv -gt 200' 'Gv -gt 90' 'Gv -lt 190' 'Bv -lt 140' \
           'Bv -gt 200' 'Rv -lt 170' 'Gv -gt 100' 'Gv -lt 220' \
           'L0 -ge 160' 'M0 -le 70' 'L1 -lt 130' 'V -ge 2'
  do
    a=$(printf '%s\n' "$OLD" | grep -cF -- "$p" || true)
    if [ "$a" = "0" ]; then
      fail "阈值模式在 v0.10.0 里就不存在: '$p' (守卫清单写错了?)"
    elif [ "$(gc "$p" water.sh)" = "0" ]; then
      fail "water.sh 丢了判定阈值 '$p' —— 阈值被改动或删除"
    fi
  done

  # --- ORANGE / BLUE 两个函数体必须逐行一致 (阈值的真正落点) ---
  for fn in ORANGE BLUE; do
    a=$(printf '%s\n' "$OLD" | grep -E "^$fn\\(\\)" | md5sum | cut -d' ' -f1)
    b=$(grep -E "^$fn\\(\\)" water.sh | md5sum | cut -d' ' -f1)
    [ "$a" = "$b" ] || fail "$fn() 的判定条件与 v0.10.0 不一致"
  done

  secdone "坐标/常量/阈值三类取值均与 v0.10.0 一致"
fi


# ============ 2. service.sh 单命中 ============
# 调度器遍历所有 profile, 命中一个就必须跳出。同一天浇两次是这个模块最恶劣的
# 失败模式(工行会重复领水), 所以判据取「命中即 break」而不是「结果只跑一次」——
# 前者是结构特征, 后者要跑起来才看得出来。
sec "2. service.sh 定时调度单命中"

n_break=$(gc '    break' service.sh)
# 循环体里应该有两处 break: FORCE 命中一处, 定时命中一处(见 service.sh 728-744)。
if [ "$n_break" -ge 2 ] 2>/dev/null; then
  ok "profile 循环内有 $n_break 处命中即 break"
else
  fail "profile 循环内只有 $n_break 处 break —— 可能会连跑多个任务"
fi

n_rp=$(gc 'run_profile $HIT ${HITF:-0}' service.sh)
if [ "$n_rp" = "1" ]; then
  ok "循环结束后 run_profile 只调用 1 次"
else
  fail "run_profile \$HIT 应恰好 1 处, 实际 $n_rp 处"
fi

n_hit=$(gc 'HIT=$PN' service.sh)
if [ "$n_hit" -ge 2 ] 2>/dev/null; then
  ok "两处命中都给 HIT 赋值"
else
  fail "HIT=\$PN 只有 $n_hit 处, 与 break 的处数不匹配"
fi


# ============ 3. app.js 的 DOM 引用 ============
# `$('x')` 是 document.getElementById 的包装。删掉 index.html 里的元素却留下引用,
# 这里不会报错, 要等运行时 .checked / .value 才抛 TypeError —— 而 app.js 是模块,
# 顶层抛一次整个 WebUI 直接白屏, 用户只会看到「打不开」。
# 这条守卫就是为删 card.time 那次改动写的。
sec "3. app.js 的 \$('#id') 都能在 index.html 找到"

IDS=$(grep -oE "\\\$\('[A-Za-z0-9_]+'\)" webroot/app.js \
      | sed -e "s/^\\\$('//" -e "s/')$//" | sort -u)
if [ -z "$IDS" ]; then
  fail "从 app.js 里一个 \$('#id') 都没提取出来 —— 正则可能写坏了"
fi
n_ref=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  n_ref=$((n_ref+1))
  if [ "$(gc "id=\"$id\"" webroot/index.html)" = "0" ]; then
    fail "app.js 引用 \$('#id') 但 index.html 没有 id=\"$id\" —— 运行时会白屏"
  fi
done <<EOF
$IDS
EOF
secdone "$n_ref 个元素引用全部有对应 id"


# ============ 4. i18n 四语键集一致 ============
# 删一个键要删四遍, 少一种语言就在那门语言里显示成 key 原文。
# 这里不比「值」只比「键集合」和「键顺序」: 值本来就不一样(是翻译)。
sec "4. i18n.js 四语键集一致"

python3 - <<'PY' || FAILS=$((FAILS+1))
import re, sys

src = open('webroot/i18n.js', encoding='utf-8').read()

# 按 `const <lang> = {` ... `};` 切块。语言块顺序写死, 与文件里的一致。
blocks = {}
for lang in ('zh', 'en', 'fr', 'ru'):
    m = re.search(r'^const %s = \{$' % lang, src, re.M)
    if not m:
        sys.exit('  FAIL 找不到 const %s = { —— 结构变了, 本守卫需要跟着更新' % lang)
    end = src.index('\n};', m.end())
    body = src[m.end():end]
    # 只取顶层的 'key': (本文件键都在顶层)
    keys = re.findall(r"^  '([^']+)':", body, re.M)
    blocks[lang] = keys

ref_name, ref = 'zh', blocks['zh']
print('  ok   zh 有 %d 个键' % len(ref))
bad = 0
for lang in ('en', 'fr', 'ru'):
    ks = blocks[lang]
    if len(ks) != len(ref):
        print('  FAIL %s 有 %d 个键, zh 有 %d 个 —— 键数不一致' % (lang, len(ks), len(ref)))
        bad += 1
        continue
    if ks != ref:
        only_zh = [k for k in ref if k not in ks]
        only_x  = [k for k in ks if k not in ref]
        if only_zh or only_x:
            print('  FAIL %s 与 zh 键集不同: zh 独有=%s %s 独有=%s'
                  % (lang, only_zh or '-', lang, only_x or '-'))
        else:
            # 集合相同但顺序不同 —— 顺序不同会让「按位置对齐」的读法读错
            diff = next(i for i, (a, b) in enumerate(zip(ref, ks)) if a != b)
            print('  FAIL %s 与 zh 键集相同但顺序不同, 第 %d 个: zh=%s %s=%s'
                  % (lang, diff + 1, ref[diff], lang, ks[diff]))
        bad += 1
    else:
        print('  ok   %s 键集与顺序均与 zh 一致 (%d)' % (lang, len(ks)))

# 两处引用点缺一不可: data-i18n 是声明式, t('...') 是命令式(徽标/提示这类拼出来的文案)
html = open('webroot/index.html', encoding='utf-8').read()
appjs = open('webroot/app.js', encoding='utf-8').read()
used = set(re.findall(r'data-i18n(?:-ph|-title)?="([^"]+)"', html))
used |= set(re.findall(r"\bt\('([^']+)'", appjs))

missing = sorted(k for k in used if k not in set(ref))
if missing:
    print('  FAIL index.html/app.js 引用了 i18n 里不存在的键: %s' % ', '.join(missing))
    bad += 1
else:
    print('  ok   引用的 %d 个键都存在' % len(used))

# 反向: 不允许留孤儿键。删一个功能往往只删了调用点、忘了删 i18n, 那几个键会永远
# 陪着发布包走下去。加这条守卫的前提是「t() 的键都是字面量」—— 本仓库没有动态拼键,
# 一旦以后引入动态拼键, 这条会开始误报, 那时候应该改成维护一份白名单, 而不是把
# 这条守卫删掉。
orphan = [k for k in ref if k not in used]
if orphan:
    print('  FAIL i18n 里有 %d 个孤儿键(没人引用, 应随功能一起删): %s'
          % (len(orphan), ', '.join(orphan)))
    bad += 1
else:
    print('  ok   %d 个键全部有引用点, 无孤儿键' % len(ref))

sys.exit(1 if bad else 0)
PY


# ============ 5. water.sh 的截图生命周期 ============
# 旧版全脚本一个 rm 都没有, 每跑一次就往 /sdcard/Download 里永久留一份
# 12.36 MB 的 zxr.raw 和若干全屏 PNG。这条守卫盯住「有清理、成功不留图、失败留证据」。
# 整节交给 python 算: 「注释里提到某文件」和「真的写了这个文件」必须分开看。
# 用 grep -v '#' 过滤注释会漏 —— 注释行如果带缩进, 它匹配不上, 于是「# 以前这里
# 会写 zx_water.png」照样被算成实写; 上一版就是这么把这条判据整个短路掉的。
sec "5. water.sh 的截图生命周期"

python3 - <<'PY' || FAILS=$((FAILS+1))
import re, sys

raw = open('water.sh', encoding='utf-8').read()
lines = raw.split('\n')

def is_code(s):
    return not s.lstrip().startswith('#')

bad = 0

# 5.1 清理必须挂在 trap 上 (脚本有正常 exit 和 4 种信号路径)
if re.search(r"^trap '.*cleanup_files.*'", raw, re.M):
    print('  ok   trap 里挂着 cleanup_files (正常退出与 4 种信号都收得到)')
else:
    print('  FAIL trap 没有调用 cleanup_files —— zxr.raw 和取证图会永久残留')
    bad += 1

# 5.2 最大头的 12.36 MB 原始帧必须被删 (只看真代码, 注释不算)
if any(is_code(l) and re.search(r'rm -f ["\']?\$RAW', l) for l in lines):
    print('  ok   cleanup_files 会删掉 12.36 MB 的 $RAW')
else:
    print('  FAIL cleanup_files 没有删除 $RAW')
    bad += 1

# 5.3 成功路径不得再写 zx_water.png —— 写了紧接着又要删 = 白做一次全屏 PNG 编码
hits = [i for i, l in enumerate(lines) if is_code(l) and 'zx_water.png' in l]
if hits:
    print('  FAIL 成功/失败路径仍在写 zx_water.png: 第 %s 行'
          % ', '.join(str(i + 1) for i in hits))
    bad += 1
else:
    print('  ok   不再生成 zx_water.png (SNAP=0 下成功路径一张 PNG 都不产生)')

# 5.4 失败必须留证据: 每一处 *_fail.png 现场截图, 前面 6 行内都要置 KEEP_FAIL=1
#      —— 否则退出时的清理会把它一起删掉, 「为什么没浇水」再也没法回溯。
fail_shots = [i for i, l in enumerate(lines)
              if is_code(l) and re.search(r'screencap .*_fail\.png', l)]
if not fail_shots:
    print('  FAIL 一处 *_fail.png 现场截图都没有 —— 失败时将无任何证据可看')
    bad += 1
else:
    for i in fail_shots:
        window = lines[max(0, i - 6):i]
        if not any(is_code(l) and re.search(r'\bKEEP_FAIL=1\b', l) for l in window):
            print('  FAIL 第 %d 行的失败截图前没有置 KEEP_FAIL=1 —— 证据会被清掉'
                  % (i + 1))
            bad += 1
    if bad == 0:
        print('  ok   %d 处失败现场截图, 每处前面都置了 KEEP_FAIL=1' % len(fail_shots))

# 5.5 SNAP 默认必须是 0 (1 会重新开始往用户相册里堆图)
if re.search(r'^SNAP=0\b', raw, re.M):
    print('  ok   SNAP 默认 0 (正常流程不生成过程取证图)')
else:
    print('  FAIL SNAP 默认值不是 0 —— 每次运行都会往 /sdcard/Download 里堆全屏 PNG')
    bad += 1

sys.exit(1 if bad else 0)
PY


# ============ 6. 内容区 md5 的字节范围 ============
# 「只改等多久」这条约束有个很隐蔽的违反方式: 坐标、阈值、原语一个没动, 但喂给
# 判定的那片像素挪了位置。v0.12.8 把 dd bs=1 换成 bs=4096 对齐就是这么滑过去的 ——
# 1464012 整除不了 4096 (两者最大公约数只有 4), 向上取整后起点偏出 y300 约 0.48 行,
# md5 跟基线再也不一样, 而守卫 1 的坐标/阈值/函数体三条断言全都照常通过。
#
# 这条守卫不读实现、不认 dd/tail/head 的写法, 直接把两边的 hash 拿去跑同一份
# 合成底片, 再按字节边界打标记: 只要范围的起点或长度差一个字节, 标记就会落进
# 一侧、落在另一侧之外, md5 立刻分家。所以以后换成任何实现都仍然受它管。
sec "6. 内容区 md5 的字节范围 vs v0.10.0"

python3 - <<'PY' || FAILS=$((FAILS+1))
import hashlib, os, re, subprocess, sys, tempfile

bad = 0

# --- 基线范围: 从 v0.10.0 tag 里把那行 dd 的算式抠出来, 不手抄 ---
try:
    old = subprocess.run(['git', 'show', 'v0.10.0:water.sh'],
                         capture_output=True, text=True, check=True).stdout
except Exception as e:
    print('  FAIL 读不到 v0.10.0:water.sh (%s)' % e)
    sys.exit(1)

m = re.search(r'dd if=\$RAW bs=1 skip=\$\(\((.*?)\)\)\s+count=\$\(\((.*?)\)\)', old)
if not m:
    print('  FAIL v0.10.0 里找不到 dd bs=1 的 skip/count 算式 —— 守卫清单需要更新')
    sys.exit(1)
skip_e, count_e = m.group(1), m.group(2)

new = open('water.sh', encoding='utf-8').read()
sw_m = re.search(r'^SW=(\d+)', new, re.M)
if not sw_m:
    print('  FAIL water.sh 里读不到 SW= —— 无法算出基线范围')
    sys.exit(1)
SW = int(sw_m.group(1))

# 算式里只有整数四则和 $SW, 用受限命名空间求值即可(本仓库自己的代码)
def ev(expr):
    return eval(re.sub(r'\$SW\b', str(SW), expr), {'__builtins__': {}}, {})

START, LENGTH = ev(skip_e), ev(count_e)
END = START + LENGTH
print('  基线范围 [%d, %d)  长度 %d  (SW=%d)' % (START, END, LENGTH, SW))

# --- 当前实现: 抽顶层赋值 + 包住 md5sum 的那个函数 ---
lines = new.split('\n')
assigns = '\n'.join(l for l in lines if re.match(r'^[A-Za-z_][A-Za-z0-9_]*=', l))

md5_i = next((i for i, l in enumerate(lines)
              if '| md5sum' in l and not l.lstrip().startswith('#')), None)
if md5_i is None:
    print('  FAIL water.sh 里没有 | md5sum 的哈希语句 —— 守卫清单需要更新')
    sys.exit(1)

body, call = None, None
for i in range(md5_i, -1, -1):
    fm = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\(\)', lines[i])
    if fm:
        for j in range(i + 1, len(lines)):
            if lines[j] == '}':
                body = '\n'.join(lines[i:j + 1])
                call = fm.group(1)
                break
        break
if body is None:
    # 内联写法(没有函数): 只取 | md5sum 之前那一段当生产者
    seg = lines[md5_i].split('| md5sum')[0].strip()
    seg = re.sub(r'^\w+=\$\(', '', seg)
    body, call = '%s() { %s; }' % ('__hash__', seg), '__hash__'

# --- 合成底片: 全 0, 再按需在边界上打一个 0x01 的标记 ---
size = END + 4096
probes = [(None, '全 0 (查长度)'), (START - 1, '起点前一字节'),
          (START, '起点字节'), (END - 1, '终点前一字节'), (END, '终点字节')]

tmp = tempfile.mkdtemp(prefix='zx_hash_guard_')
try:
    with open(os.path.join(tmp, 't.bin'), 'wb') as f:
        f.write(bytes(size))
    path = os.path.join(tmp, 't.bin')

    script = os.path.join(tmp, 'h.sh')
    with open(script, 'w') as f:
        f.write(assigns + '\n' + body + '\nRAW="$1"\n%s\n' % call)

    for pos, label in probes:
        with open(path, 'r+b') as f:
            f.truncate(size)
            f.seek(0); f.write(bytes(size))
            if pos is not None:
                if not (0 <= pos < size):
                    print('  FAIL 探针位置 %d 越界' % pos); bad += 1; continue
                f.seek(pos); f.write(b'\x01')

        data = open(path, 'rb').read()
        base = hashlib.md5(data[START:END]).hexdigest()
        got = subprocess.run(['sh', script, path],
                             capture_output=True, text=True).stdout.strip()
        if got == base:
            print('  ok   %s -> md5 %s 与基线一致' % (label, base[:16]))
        else:
            print('  FAIL %s -> md5 %s, 基线 %s  —— 喂给判定的像素范围变了'
                  % (label, got[:16] or '(空)', base[:16]))
            bad += 1
finally:
    subprocess.run(['rm', '-rf', tmp])

if bad == 0:
    print('  ok   5 个边界探针全部一致 = 内容区范围与 v0.10.0 逐字节相同')
sys.exit(1 if bad else 0)
PY


# ============ 7. 设备档案的显示形态/存储形态 ============
# 事故: v0.12.9 的「自动检测 → 保存」必然失败, 而当时六条守卫全绿。
#   device.conf 的标签键只认 [A-Za-z0-9_.-], 于是约定「存下划线、显空格」:
#   devParse 读回来把 _ 还原成空格, devSave 落盘前必须再转回下划线。
#   旧版拿显示形态直接撞正则, 而 loadDevice() 兜底给的是 'Xiaomi 17 Pro'(带空格)
#   —— 必然失败, 校验在发请求之前就 return, 后端一个字节都收不到。用户看到的是
#   「点保存没反应」, 报错文案又不带字段名, 只能判定成「保存功能坏了」。
#
# 这条守卫只钉「先转换再校验」这个不变量, 不管具体写法:
# 标签正则的实参只可能是转过的 model/label, 出现任何 .value 就是回归。
sec "7. 设备档案的显示形态/存储形态转换"

python3 - <<'PY' || FAILS=$((FAILS+1))
import io, re, sys

bad = 0
src = io.open('webroot/app.js', encoding='utf-8').read()

def cut(a, b, what):
    i = src.find(a)
    if i < 0:
        print('  FAIL 找不到 %s 的起点 —— 结构变了, 本守卫需要跟着更新' % what)
        return None
    j = src.find(b, i)
    if j < 0:
        print('  FAIL 找不到 %s 的终点 —— 结构变了, 本守卫需要跟着更新' % what)
        return None
    return src[i:j]

def check(cond, msg):
    global bad
    if cond:
        print('  ok   %s' % msg)
    else:
        print('  FAIL %s' % msg)
        bad += 1

save = cut('async function devSave()', '// 设备卡事件挂载', 'devSave')
pars = cut('function devParse', 'async function loadDevice', 'devParse')
isfn = cut('function isErr(', '// ---------- 状态加载', 'isErr')
if save is None or pars is None or isfn is None:
    sys.exit(1)

check('function devToStore(' in src, 'devToStore 函数存在')
check(r"replace(/\s+/g, '_')" in src, 'devToStore 把空白转成下划线')

check(re.search(r'const\s+model\s*=\s*devToStore\s*\(', save) is not None,
      'devSave 的 model 先过 devToStore')
check(re.search(r'const\s+label\s*=\s*devToStore\s*\(', save) is not None,
      'devSave 的 label 先过 devToStore')

# 标签正则只允许作用在转换后的变量上 —— 拿 .value 直接校验就是 v0.12.9 的原 bug
MARK = '/^[A-Za-z0-9_.-]+$/.test('
args = []
i = 0
while True:
    k = save.find(MARK, i)
    if k < 0:
        break
    j = save.find(')', k + len(MARK))
    args.append(save[k + len(MARK):j])
    i = k + 1
check(len(args) == 2 and set(args) <= {'model', 'label'},
      '标签正则只作用在转换后的变量上 (实参=%s)' % (args or '无'))

check(re.search(r"d\[m\[1\]\]\s*=\s*\(m\[1\]\s*===\s*'DEV_LABEL'\)", pars) is not None,
      'devParse 只把 DEV_LABEL 还原成空格 (不污染 DEV_MODEL)')

check("args.push('DEV_LABEL=' + label)" in save, 'DEV_LABEL 发送的是转换后的 label')
check("args.push('DEV_MODEL=' + model)" in save, 'DEV_MODEL 发送的是转换后的 model')

check("s.indexOf('EXEC_ERR') === 0" in isfn,
      'isErr 同时认 ERR 与 EXEC_ERR, 否则桥失败会弹「已保存」假成功')

check("t('dev.bad.fields'" in save, '校验失败会带出字段名, 不再只说「参数不合法」')

sys.exit(1 if bad else 0)
PY


# ============ 汇总 ============
printf '\n'
if [ "$FAILS" = "0" ]; then
  echo "回归守卫: 全部通过"
  exit 0
fi
echo "回归守卫: $FAILS 条失败"
exit 1
