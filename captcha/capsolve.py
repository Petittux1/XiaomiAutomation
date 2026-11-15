# icbc_daily_water / captcha/capsolve.py  验证码识别与求解 (纯图像, numpy + Pillow)
# 只在回放/录制期间由 captcha.sh 拉起, 会话结束即退出; 详见 .agent/captcha_impl.md。
#   python capsolve.py detect IMG          -> 一行 JSON (离线检测/规划, 不注入任何输入)
#   python capsolve.py worker MODE OWNER IN OUT FLAG
#        MODE=replay: 从 IN(FIFO) 读 "check", 截屏->检测->求解, 向 OUT 回一行结果
#        MODE=record: 每 ~0.7 s 截屏检测; 发现验证码时建 FLAG(录制据此暂停), 求解, 消失后删 FLAG
# 类型: icon(图标点选, 有真机样本) / word(文字点选, 需可选 ddddocr) / slider(滑块); 后两者未经真机验证。
import itertools, json, os, select, struct, subprocess, sys, time

if "site" not in sys.modules:
    # captcha.sh 以 -I -S 启动 (root 跑 Termux 的解释器): 不读 PYTHON* 环境变量、不加用户 site、
    # 不执行 site-packages 里的 .pth / sitecustomize; 这里只把解释器自带的 site-packages 加回来。
    sys.path.append(os.path.join(sys.prefix, "lib", "python%d.%d" % sys.version_info[:2], "site-packages"))

import numpy as np
from PIL import Image, ImageFilter

DISPLAY = os.environ.get("CAP_DISPLAY", "")
LOGF = os.environ.get("CAP_LOG", "")
REFRESH_MAX = int(os.environ.get("CAP_REFRESH_MAX", "8"))   # 解不出就持续换图, 用完才认输
REFRESH_GAP = 3.5        # 两次刷新之间至少间隔 (秒), 防厂商「尝试过多」限流
# 录制模式: 求解在后台跑, 不暂停录取。求解器用 /system/bin/input 注入, 事件走
# InputManager, 不会出现在 record.sh 监听的 /dev/input/event* 硬件流里 —— 旧闸门
# 实际丢掉的是用户自己的手势。真机 15:47-15:49: solve() 变成 8 次刷新/240 s 长循环,
# 闸门全程存在, 用户 20-30 s 的录制整段 Empty。默认关, CAP_RECORD_GATE=1 可恢复旧行为。
RECORD_GATE = os.environ.get("CAP_RECORD_GATE", "0") != "0"
RECORD_REFRESH_MAX = int(os.environ.get("CAP_RECORD_REFRESH_MAX", "4"))
RECORD_SOLVE_BUDGET = float(os.environ.get("CAP_RECORD_SOLVE_BUDGET", "35"))
LOCK_WAIT = float(os.environ.get("CAP_LOCK_WAIT", "20"))    # 厂商锁冷却 (秒)
LOCK_MAX = int(os.environ.get("CAP_LOCK_MAX", "3"))         # 最多等几次锁
SOLVE_BUDGET = float(os.environ.get("CAP_SOLVE_BUDGET", "240"))  # 单次求解总预算 (秒)
GONE_WAIT = float(os.environ.get("CAP_GONE_WAIT", "5.0"))   # 提交后等结果 (秒), 太短会误刷新掉慢一拍的成功
TAP_GAP = 0.8            # 点选间隔, 真机验证 0.8 s 可通过
HINT_MIN_DARK = int(os.environ.get("CAP_HINT_MIN_DARK", "3"))   # Geetest 深色面板固定 3 个提示图
TAP_MIN_DIST = float(os.environ.get("CAP_TAP_MIN_DIST", "48"))  # 两次点选的最小间距 (px)
BADGE_CHECK = os.environ.get("CAP_BADGE_CHECK", "1") != "0"     # 半截编号圆标 -> 刷新
ICON_MIN = float(os.environ.get("CAP_ICON_MIN", "0.60"))  # 图标匹配最低分, 低于则刷新
# 补充放行门槛: 有一项匹配极好 + 没有明显错的项时, 不再被均值下限误杀。
# 依据 .agent/fixtures 实测: 7 张正样本的最高分均 >= 0.911; 唯一「已点过、
# 不能再点」的负样本 scores=[0.687,0.678,0.637] 最高分只有 0.687。
ICON_STRONG = float(os.environ.get("CAP_ICON_STRONG", "0.85"))
ICON_FLOOR = float(os.environ.get("CAP_ICON_FLOOR", "0.55"))
STAMP = os.environ.get("CAP_STAMP", "")   # 上次刷新时刻, 跨回放尝试持久化 (保证刷新间隔)
OWNER = 0                                 # worker 的主人 PID; 每次注入前确认它还活着


class OwnerGone(SystemExit):
    pass


def owner_alive():
    if not OWNER:
        return True
    try:
        os.kill(OWNER, 0)
        return True
    except OSError:
        return False


def log(msg):
    line = time.strftime("%m%d-%H%M%S") + " CAPTCHA " + msg
    if LOGF:
        try:
            with open(LOGF, "a") as f:
                f.write(line + "\n")
        except OSError:
            pass
    else:
        print(line, file=sys.stderr)


# ---------------- 图像读取 ----------------
def from_raw(data):
    """screencap 无 -p 的原始输出: w,h,fmt[,dataspace] 头 + RGBA 像素。"""
    w, h, fmt = struct.unpack("<III", data[:12])
    hdr = len(data) - w * h * 4
    if w < 100 or h < 100 or hdr not in (12, 16):
        raise ValueError("raw screencap header w=%d h=%d hdr=%d" % (w, h, hdr))
    a = np.frombuffer(data, np.uint8, count=w * h * 4, offset=hdr).reshape(h, w, 4)
    return a[..., 2::-1] if fmt == 5 else a[..., :3]   # 5 = BGRA_8888


def load(path):
    with open(path, "rb") as f:
        head = f.read(8)
    if head.startswith(b"\x89PNG") or head[:2] == b"\xff\xd8":
        return np.asarray(Image.open(path).convert("RGB"))
    with open(path, "rb") as f:
        return from_raw(f.read())


# 系统程序不能继承 Termux 的 LD_LIBRARY_PATH (真机: screencap 报 cannot find libmediandk.so)
SYS_ENV = {k: v for k, v in os.environ.items() if k not in ("LD_LIBRARY_PATH", "LD_PRELOAD")}
SYS_ENV["PATH"] = "/system/bin:/system/xbin:/vendor/bin"


def _sys(cmd, out=subprocess.DEVNULL, timeout=15):
    return subprocess.run(cmd, stdout=out, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, env=SYS_ENV, timeout=timeout)


def pick_display():
    """多屏机型 (17 Pro 有背屏) 不指定 -d 时 screencap 只是「碰巧」取第一块; 取面积最大的那块 = 主屏。"""
    global DISPLAY
    if DISPLAY:
        return DISPLAY
    try:
        txt = _sys(["/system/bin/dumpsys", "SurfaceFlinger", "--display-id"], out=subprocess.PIPE).stdout.decode("utf-8", "replace")
    except Exception:
        return ""
    ids = [ln.split()[1] for ln in txt.splitlines() if ln.startswith("Display ") and len(ln.split()) > 1 and ln.split()[1].isdigit()]
    if len(ids) > 1:
        best = 0
        for i in ids:
            try:
                head = _sys(["/system/bin/screencap", "-d", i], out=subprocess.PIPE).stdout[:8]
                w, h = struct.unpack("<II", head)
            except Exception:
                continue
            if w * h > best:
                best, DISPLAY = w * h, i
    return DISPLAY


def capture():
    r = _sys(["/system/bin/screencap"] + (["-d", DISPLAY] if DISPLAY else []), out=subprocess.PIPE, timeout=10)
    return from_raw(r.stdout)


# ---------------- 连通域 (行程编码 + 并查集, 无 scipy) ----------------
def components(mask):
    """8 连通域。返回 (label 图, [(x0,y0,x1,y1,area), ...]), label 从 1 开始。"""
    h, w = mask.shape
    m = np.zeros((h, w + 2), np.int8)
    m[:, 1:-1] = mask
    d = np.diff(m, axis=1)
    ry, rs = np.nonzero(d == 1)
    _, re_ = np.nonzero(d == -1)       # 按行优先顺序, 起止一一对应
    n = len(ry)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    rowstart = np.searchsorted(ry, np.arange(h + 1))
    for y in range(1, h):
        a0, a1 = rowstart[y - 1], rowstart[y]
        b0, b1 = rowstart[y], rowstart[y + 1]
        i, j = a0, b0
        while i < a1 and j < b1:
            # 8 连通: [s, e) 与 [s', e') 在扩 1 后相交
            if rs[i] <= re_[j] and rs[j] <= re_[i]:
                ri, rj = find(i), find(j)
                if ri != rj:
                    parent[max(ri, rj)] = min(ri, rj)
            if re_[i] < re_[j]:
                i += 1
            else:
                j += 1
    roots = np.array([find(i) for i in range(n)], dtype=np.int64)
    uniq, lab = np.unique(roots, return_inverse=True)
    lab = lab + 1
    out = np.zeros((h, w), np.int32)
    boxes = [[w, h, -1, -1, 0] for _ in uniq]
    for k in range(n):
        y, s, e, L = int(ry[k]), int(rs[k]), int(re_[k]), int(lab[k])
        out[y, s:e] = L
        b = boxes[L - 1]
        if s < b[0]: b[0] = s
        if y < b[1]: b[1] = y
        if e > b[2]: b[2] = e
        if y + 1 > b[3]: b[3] = y + 1
        b[4] += e - s
    return out, [tuple(b) for b in boxes]


def dilate(mask, r):
    """方形 (2r+1) 膨胀, 可分离的移位 OR (PIL MaxFilter 在 r=5 时慢 40 倍)。"""
    if r <= 0:
        return mask
    m = mask.astype(bool)
    h = m.copy()
    for s in range(1, r + 1):
        h[:, s:] |= m[:, :-s]
        h[:, :-s] |= m[:, s:]
    v = h.copy()
    for s in range(1, r + 1):
        v[s:] |= h[:-s]
        v[:-s] |= h[s:]
    return v


def runs(v, thr, gap=0):
    """v > thr 的最长连续段 (允许 gap 个元素的断口) -> (start, end) 或 None。"""
    best, cur, miss = None, None, 0
    for i, x in enumerate(v):
        if x > thr:
            if cur is None:
                cur = [i, i + 1]
            cur[1] = i + 1
            miss = 0
        elif cur is not None:
            miss += 1
            if miss > gap:
                if best is None or cur[1] - cur[0] > best[1] - best[0]:
                    best = tuple(cur)
                cur, miss = None, 0
    if cur is not None and (best is None or cur[1] - cur[0] > best[1] - best[0]):
        best = tuple(cur)
    return best


# ---------------- 结构检测: 白色弹窗 / 题头 / 图片 / 按钮 ----------------
S = 4  # 粗检测下采样步长


def find_modal(img):
    """遮罩上的弹窗 -> (x0,y0,x1,y1) 全分辨率, 否则 None。两种极性:
    白底弹窗 (暗遮罩上的白块, 厂商通用), 或深色面板 (Geetest 深色皮肤 / Chrome 强制暗色)。"""
    sm = img[::S, ::S]
    H, W = sm.shape[:2]
    lum = sm.mean(2)
    mx = sm.max(2).astype(np.int16)
    mn = sm.min(2)
    for pol, mask in (("light", mn >= 235), ("dark", (mx - mn < 28) & (lum < 95))):
        _, boxes = components(mask)
        best = None
        for (x0, y0, x1, y1, area) in boxes:
            bw, bh = x1 - x0, y1 - y0
            if bw < 0.45 * W or bh < 0.12 * H or x0 < 2 or x1 > W - 2 or y0 < 2 or y1 > H - 2:
                continue
            m = 4
            ring = np.concatenate([lum[max(0, y0 - m):y0, x0:x1].ravel(), lum[y1:y1 + m, x0:x1].ravel(),
                                   lum[y0:y1, max(0, x0 - m):x0].ravel(), lum[y0:y1, x1:x1 + m].ravel()])
            if ring.size == 0:
                continue
            if pol == "light":
                if ring.mean() > 150:   # 弹窗外必须是压暗的遮罩 (灰蒙层 ~127 也算)
                    continue
            else:
                # 深色面板: 面板内要有亮内容 (题头/提示块), 且外环与面板亮度差明显 (整屏暗底不算)
                inside = lum[y0:y1, x0:x1]
                if (inside > 170).mean() < 0.004 or abs(ring.mean() - inside.mean()) < 12:
                    continue
            if best is None or bw * bh > best[2] * best[3]:
                best = (x0, y0, bw, bh)
        if best is not None:
            x0, y0, bw, bh = best
            return (x0 * S, y0 * S, (x0 + bw) * S, (y0 + bh) * S)
    return None


def panel_color(img, modal):
    """弹窗面板底色: 顶部条带的中位色。亮面板 (厂商白底) -> 均值 >= 95, 深色面板 -> < 95。"""
    x0, y0, x1, y1 = modal
    return np.median(img[y0:min(y1, y0 + 40), x0:x1].reshape(-1, 3), axis=0)


def find_photo(img, modal):
    x0, y0, x1, y1 = modal
    reg = img[y0:y1:2, x0:x1:2].astype(np.int16)
    pcol = panel_color(img, modal)
    if pcol.mean() < 95:   # 深色面板: 图片 = 与面板底色差明显或彩度高的区域 (图片暗部/深蓝底也算)
        nonp = (np.abs(reg - pcol).max(2) > 25) | (reg.max(2) - reg.min(2) > 30)
    else:                  # 白弹窗: 图片 = 非白区域
        nonp = reg.min(2) < 235
    r = runs(nonp.mean(1), 0.6, gap=3)
    if r is None:
        return None
    py0, py1 = r
    c = runs(nonp[py0:py1].mean(0), 0.6, gap=3)
    if c is None:
        return None
    px0, px1 = c
    pw, ph = (px1 - px0) * 2, (py1 - py0) * 2
    if pw < 0.5 * (x1 - x0) or ph < 0.25 * (y1 - y0):
        return None
    return (x0 + px0 * 2, y0 + py0 * 2, x0 + px1 * 2, y0 + py1 * 2)


def find_hint_box(img, modal, photo):
    """题头里的提示图: 亮面板 = 一块非纯白的实心矩形, 内含灰色线稿图标;
    深色面板 = 题头右侧一排亮色提示块 (白描边图标, Geetest), 文字块更矮被排除。"""
    x0, y0, x1, y1 = modal
    hy1 = photo[1]
    reg = img[y0:hy1, x0:x1]
    if reg.shape[0] < 20:
        return None
    if panel_color(img, modal).mean() >= 95:
        m = reg.min(2) < 254
        lab, boxes = components(m)
        best = None
        for (bx0, by0, bx1, by1, area) in boxes:
            bw, bh = bx1 - bx0, by1 - by0
            if bw < 60 or bh < 40 or area < 0.85 * bw * bh:
                continue
            if bw > 0.9 * (x1 - x0):
                continue
            if best is None or area > best[4]:
                best = (bx0, by0, bx1, by1, area)
        if best is None:
            return None
        return (x0 + best[0], y0 + best[1], x0 + best[2], y0 + best[3])
    m = reg.mean(2) > 150
    _, boxes = components(dilate(m, 3))
    ux0 = uy0 = 10 ** 9
    ux1 = uy1 = -1
    for (bx0, by0, bx1, by1, area) in boxes:
        bw, bh = bx1 - bx0, by1 - by0
        # 汉字块膨胀后高 <= 57, 提示块 (白描边图标+方框) 高 ~77+; 边缘竖条被 bw 下限挡掉
        if bh < 65 or bw < 40 or bw > 0.25 * (x1 - x0):
            continue
        ux0, uy0, ux1, uy1 = min(ux0, bx0), min(uy0, by0), max(ux1, bx1), max(uy1, by1)
    if ux1 < 0:
        return None
    return (x0 + ux0, y0 + uy0, x0 + ux1, y0 + uy1)


def find_buttons(img, modal, photo):
    """图片下方按钮栏: 最大的蓝色块 = 确认; 小图标按 x 排序 = [关闭, 刷新, ...]
    (亮面板上是灰色小图标, 深色面板上是亮色描边图标)。"""
    x0, _, x1, y1 = modal
    by0 = photo[3]
    reg = img[by0:y1, x0:x1].astype(np.int16)
    if reg.shape[0] < 20:
        return None, []
    r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
    darkp = panel_color(img, modal).mean() < 95
    if darkp:   # 深色面板: 确认按钮是暗蓝 (68,81,126), b > 150 会漏掉
        blue = (b - r > 30) & (b > 100)
    else:
        blue = (b - r > 30) & (b > 150)
    _, boxes = components(blue)
    confirm = None
    big = [bx for bx in boxes if bx[4] > 2000]
    if big:
        bx = max(big, key=lambda t: t[4])
        confirm = (x0 + (bx[0] + bx[2]) // 2, by0 + (bx[1] + bx[3]) // 2)
    if darkp:
        grey = reg.mean(2) > 100   # 深色面板页脚小图标是中灰 (126)
    else:
        grey = (reg.max(2) < 200) & (reg.max(2) - reg.min(2) < 30)
    _, gb = components(dilate(grey, 3))
    # 刷新图标是上下两段弧: 横向中心相近的块并成一个图标
    groups = []
    for bx in sorted((b for b in gb if b[4] > 100), key=lambda t: t[0] + t[2]):
        if groups and abs((bx[0] + bx[2]) - (groups[-1][0] + groups[-1][2])) < 60:
            g = groups[-1]
            groups[-1] = [min(g[0], bx[0]), min(g[1], bx[1]), max(g[2], bx[2]), max(g[3], bx[3])]
        else:
            groups.append(list(bx[:4]))
    icons = []
    for (gx0, gy0, gx1, gy1) in groups:
        w, h = gx1 - gx0, gy1 - gy0
        if 30 <= w <= 140 and 30 <= h <= 140 and 0.6 < w / h < 1.6:
            cx = x0 + (gx0 + gx1) // 2
            if confirm is None or cx < confirm[0] - 150:
                icons.append((cx, by0 + (gy0 + gy1) // 2))
    icons.sort()
    if darkp and icons:
        # 深色页脚固定为 [关闭X, 刷新, 反馈, 声音]: 刷新是两段断弧, 图标中带 (行 1/3..2/3)
        # 占用率明显低于其它三个 (实测 0.23 vs 0.42+)。按形状选, 选不出唯一一个就不给刷新钮
        # (宁可等厂商自动换图, 也绝不误点关闭)。位置序 (icons[1]) 在帧间不稳定, 会点到关闭。
        picked = []
        for (cx, cy) in icons:
            ry, rx = cy - by0, cx - x0
            crop = reg[max(0, ry - 40):ry + 40, max(0, rx - 40):rx + 40]
            if crop.shape[0] < 60 or crop.shape[1] < 60:
                continue
            gm = crop.mean(2) > 100
            mid = float(gm.mean(1)[gm.shape[0] // 3: gm.shape[0] * 2 // 3].max())
            if mid < 0.32:
                picked.append((cx, cy))
        icons = picked if len(picked) == 1 else []
    return confirm, icons


def find_slider_track(img, modal, photo):
    """图片下方横跨的滑轨 (非白, 宽 >= 图片 70%, 高 30..160)。
    深色面板 (Geetest): 滑轨是略亮于面板的暗条 (色差 ~15), 滑钮是蓝块。"""
    x0, _, x1, y1 = modal
    reg = img[photo[3]:y1, photo[0]:photo[2]]
    if reg.shape[0] < 30:
        return None, None
    darkp = panel_color(img, modal).mean() < 95
    if darkp:
        pcol = panel_color(img, modal)
        nonw = np.abs(reg.astype(np.int16) - pcol).max(2) > 14
    else:
        nonw = reg.min(2) < 245
    r = runs(nonw.mean(1), 0.7, gap=2)
    if r is None or not (30 <= r[1] - r[0] <= 160):
        return None, None
    ty0, ty1 = photo[3] + r[0], photo[3] + r[1]
    trk = img[ty0:ty1, photo[0]:photo[2]].astype(np.int16)
    tw = trk.shape[1]
    # 滑钮: 轨道左端一块与轨道底色明显不同的方块 (宽 5%..25% 轨长; Geetest 滑钮宽 ~27%)
    base = np.median(trk[:, tw // 2:].reshape(-1, 3), axis=0)
    cols = np.nonzero((np.abs(trk - base).sum(2) > 60).mean(0) > 0.5)[0]
    if not len(cols) or cols[0] > 0.1 * tw:
        return None, None
    run = runs(np.isin(np.arange(tw), cols).astype(float), 0.5)
    wmax = 0.32 if darkp else 0.25
    if run is None or run[0] > 0.1 * tw or not (0.05 * tw <= run[1] - run[0] <= wmax * tw):
        return None, None
    return (photo[0], ty0, photo[2], ty1), (photo[0] + (run[0] + run[1]) // 2, (ty0 + ty1) // 2)


def detect(img):
    """-> dict(kind=none|icon|word|slider, ...) ; kind=none 时可带 modal(无图片的白框, 如「尝试过多」)。
    只做结构判断, 不注入输入。word 还要等 OCR 读出题头「点击」才算数 (见 plan_word)。"""
    modal = find_modal(img)
    if modal is None:
        return {"kind": "none"}
    photo = find_photo(img, modal)
    if photo is None:
        # 无图白框: 厂商「尝试过多」锁 (红色实心圆标) 单独标成 locked, 调用方按失败处理
        return {"kind": "locked" if find_lock(img, modal) else "none", "modal": modal}
    d = {"kind": "none", "modal": modal, "photo": photo}
    track, handle = find_slider_track(img, modal, photo)
    if track is not None:
        d.update(kind="slider", track=track, handle=handle)
        return d
    confirm, icons = find_buttons(img, modal, photo)
    d.update(confirm=confirm, refresh=icons[1] if len(icons) >= 2 else (icons[0] if icons else None))
    hint = find_hint_box(img, modal, photo)
    if hint is not None:
        n = len(split_hint(img, hint))
        if 2 <= n <= 5 and confirm is not None:
            d.update(kind="icon", hint=hint, n=n)
        return d
    head = img[modal[1]:photo[1], modal[0]:modal[2]]
    # 文字点选候选: 题头有字 + 图片 + 图片下方的刷新/关闭小图标。仍只是候选 ——
    # 题头 OCR 必须读出「依次点击…」句式才会动手 (plan_word), 普通「点击领取」弹窗到此为止。
    # 深色面板 (Geetest) 整头都是暗底, 此规则必误报, 只对亮面板开放。
    if panel_color(img, modal).mean() >= 95 and (head.max(2) < 110).sum() > 300 and icons:
        d["kind"] = "word"
    return d


def find_lock(img, modal):
    """无图白框里的红色实心圆 (fixtures/xmsq_icon_7_toomany: 「尝试过多」)。"""
    x0, y0, x1, y1 = modal
    reg = img[y0:y1:2, x0:x1:2].astype(np.int16)
    r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
    red = (r > 170) & (r - g > 60) & (r - b > 60)
    _, boxes = components(red)
    for (bx0, by0, bx1, by1, area) in boxes:
        w, h = bx1 - bx0, by1 - by0
        if 18 <= w <= 70 and 18 <= h <= 70 and 0.75 < w / h < 1.33 and area >= 0.5 * w * h:
            return True
    return False


# ---------------- 图标点选 ----------------
def split_hint(img, hint):
    """提示图 -> 每个图标的 bool 掩码列表 (左到右)。相邻图标可能粘连: 按墨迹高度估个数再在投影谷底切。
    深色提示块 (Geetest): 墨迹 = 亮色描边; 亮面板: 墨迹 = 深色笔画。"""
    x0, y0, x1, y1 = hint
    reg = img[y0:y1, x0:x1].astype(np.int16)
    if np.median(reg.reshape(-1, 3), axis=0).mean() < 95:
        ink = reg.mean(2) > 150
    else:
        ink = reg.mean(2) < 200
    ys = np.nonzero(ink.any(1))[0]
    if len(ys) < 10:
        return []
    ink = ink[ys[0]:ys[-1] + 1]
    H = ink.shape[0]
    pitch = 0.75 * (y1 - y0)   # 提示图里图标的槽宽 ~ 0.75 x 提示图高 (粘连时据此估个数)
    col = ink.sum(0)
    segs, cur = [], None
    for x, v in enumerate(col):
        if v > 0:
            cur = [x, x + 1] if cur is None else [cur[0], x + 1]
        elif cur is not None:
            segs.append(cur); cur = None
    if cur is not None:
        segs.append(cur)
    # 并掉窄碎片 (同一图标被空列断开)
    merged = []
    for s in segs:
        if merged and (s[1] - s[0] < 0.35 * H or merged[-1][1] - merged[-1][0] < 0.35 * H) and s[0] - merged[-1][1] < 0.25 * H:
            merged[-1][1] = s[1]
        else:
            merged.append(list(s))
    out = []
    for s0, s1 in merged:
        w = s1 - s0
        if w < 0.25 * H:
            continue
        n = max(1, int(round(w / pitch)))
        cuts = [s0]
        for k in range(1, n):
            c = s0 + w * k // n
            lo, hi = c - int(0.25 * H), c + int(0.25 * H)
            cuts.append(lo + int(np.argmin(col[lo:hi])))
        cuts.append(s1)
        for a, b in zip(cuts, cuts[1:]):
            m = np.zeros_like(ink)
            m[:, a:b] = ink[:, a:b]
            sub = m[:, a:b]
            yy = np.nonzero(sub.any(1))[0]
            if len(yy) and sub.sum() > 30:
                out.append((sub[yy[0]:yy[-1] + 1], (x0 + (a + b) // 2, y0 + ys[0] + (yy[0] + yy[-1]) // 2)))
    return out


def icon_candidates(img, photo, step=2, sd_max=10):
    """图片中纯色图标 -> [(mask, (cx, cy) 全分辨率, bbox), ...]。sd_max: 掩码内颜色波动上限
    (渐变色块拒绝); 深色渲染 (Chrome 强制暗色) 抖动噪声大, 调用方可放宽。"""
    x0, y0, x1, y1 = photo
    P = img[y0:y1:step, x0:x1:step].astype(np.int16)
    U = [np.ascontiguousarray(img[y0:y1:step, x0:x1:step, ch]) for ch in range(3)]
    h, w = P.shape[:2]
    mx, mn = P.max(2), P.min(2)
    chroma = mx - mn
    flat = np.ones((h, w), bool)
    for dy, dx in ((0, 1), (1, 0)):
        dd = np.abs(P[dy:, dx:] - P[:h - dy, :w - dx]).max(2) < 8
        flat[:h - dy, :w - dx] &= dd
        flat[dy:, dx:] &= dd
    seed = flat & (chroma >= 70) & (mx >= 90)
    if seed.sum() < 50:
        return []
    q = (P[seed] // 24).astype(np.int32)
    keys = q[:, 0] * 4096 + q[:, 1] * 64 + q[:, 2]
    uk, cnt = np.unique(keys, return_counts=True)
    order = np.argsort(-cnt)
    minpix = 0.002 * w * h        # 图标笔画面积下限 (描边式图标 ~500 px; 实心式 ~1000 px @ 494x494)
    seen = np.zeros((h, w), bool)
    cands = []
    cols = P[seed]
    done = []
    for idx in order[:40]:
        if cnt[idx] < minpix * 0.25:
            break
        c = np.median(cols[keys == uk[idx]], axis=0)
        if any(np.abs(c - e).max() <= 10 for e in done):
            continue
        done.append(c)
        ar = np.arange(256)
        cm = np.ones((h, w), bool)
        for ch in range(3):   # 逐通道查表比 |P-c|.max(2) 快一个量级
            cm &= (np.abs(ar - c[ch]) <= 26)[U[ch]]
        cm &= ~seen
        if cm.sum() < minpix:
            continue
        lab, boxes = components(dilate(cm, 5))
        for L, (bx0, by0, bx1, by1, _) in enumerate(boxes, 1):
            bw, bh = bx1 - bx0, by1 - by0
            if not (0.05 * w <= max(bw, bh) <= 0.40 * w and min(bw, bh) >= 0.03 * w):
                continue
            sub = (lab[by0:by1, bx0:bx1] == L) & cm[by0:by1, bx0:bx1]
            area = int(sub.sum())
            dens = area / float(bw * bh)
            if area < minpix or not (0.06 <= dens <= 0.70):
                continue
            box = P[by0:by1, bx0:bx1]
            sd = float(box[sub].std(0).max())
            # 纯色图标边缘是硬边: 掩码外 2..3 px 的一圈与图标色差很大; 天空/草地色块是渐变
            ring = dilate(sub, 3) & ~dilate(sub, 1)
            if not ring.any():
                continue
            jump = float((np.abs(box[ring] - c).max(1) > 60).mean())
            if sd > sd_max or jump < 0.5:
                continue
            seen[by0:by1, bx0:bx1] |= sub
            cx = x0 + step * (bx0 + bx1) // 2
            cy = y0 + step * (by0 + by1) // 2
            cands.append((sub, (int(cx), int(cy)), (bx0, by0, bx1, by1), round(sd, 1), area, round(jump, 2)))
    return cands


def polar(mask, K=18, A=72):
    """旋转/缩放归一的极坐标采样 (重心 + 回转半径), 先按尺度模糊以抵消线宽差异。"""
    m = mask.astype(np.float32)
    ys, xs = np.nonzero(mask)
    cy, cx = ys.mean(), xs.mean()
    rg = float(np.sqrt(((ys - cy) ** 2 + (xs - cx) ** 2).mean())) + 1e-3
    pad = int(rg * 2) + 4
    big = np.pad(m, pad)
    blur = np.asarray(Image.fromarray((big * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(max(1.0, rg * 0.12))), np.float32) / 255
    rr = rg * np.linspace(0.1, 1.9, K)
    th = np.linspace(0, 2 * np.pi, A, endpoint=False)
    X = (cx + pad + rr[:, None] * np.cos(th)[None]).round().astype(int)
    Y = (cy + pad + rr[:, None] * np.sin(th)[None]).round().astype(int)
    X = np.clip(X, 0, big.shape[1] - 1)
    Y = np.clip(Y, 0, big.shape[0] - 1)
    p = blur[Y, X]
    p = p - p.mean()
    return p / (np.linalg.norm(p) + 1e-6)


def polar_sim(p, q):
    """两极坐标图在所有旋转下的最大归一化相关 (沿角度轴 FFT 环形相关)。"""
    c = np.fft.irfft((np.fft.rfft(p, axis=1) * np.conj(np.fft.rfft(q, axis=1))).sum(0), n=p.shape[1])
    return float(c.max())


def icon_scores_ok(scores):
    """是否按 best 排列点击图标。
    常规: 单项 >= ICON_MIN 且均值 >= ICON_MIN+0.15。
    补充: 有一项极好 (>= ICON_STRONG) 且没有明显错的项 (>= ICON_FLOOR) 也放行,
    因为「一项极好 + 其余中等」是正确匹配的常见形态, 均值门槛会误杀它。
    """
    if not scores:
        return False
    if min(scores) >= ICON_MIN and sum(scores) / len(scores) >= ICON_MIN + 0.15:
        return True
    return max(scores) >= ICON_STRONG and min(scores) >= ICON_FLOOR


def photo_sig(img, d):
    """图片区域的低分辨率指纹: 判断刷新后厂商是否真的换了题 (而不是还停在旧图/加载帧)。"""
    p = d.get("photo")
    if not p:
        return None
    x0, y0, x1, y1 = p
    a = img[y0:y1:16, x0:x1:16]
    return a.astype(np.int16) if a.size else None


def has_badge(img, photo):
    """图上是否已有编号圆标 (白心 + 蓝环) —— 即「点到一半」的残局。
    Geetest 每次点选都会在图上盖一个编号圆标, 它会被 icon_candidates 当成纯色图标,
    继续规划只会点到圆标或重复点; 正确做法是刷新换一张新图重新开始。
    只认高对比蓝环 (实测真机圆标 ring 占比 0.47~0.55, 彩色图标 <0.15), 避免误伤。"""
    x0, y0, x1, y1 = photo
    R = img[y0:y1:2, x0:x1:2].astype(np.int16)
    if R.size == 0:
        return False
    r, g, b = R[..., 0], R[..., 1], R[..., 2]
    white = (R.min(2) > 190) & (R.max(2) - R.min(2) < 45)
    blue = (b - r > 35) & (b > 110) & (g > 70)
    lab, boxes = components(dilate(white, 1))
    for L, (bx0, by0, bx1, by1, area) in enumerate(boxes, 1):
        w, h = (bx1 - bx0) * 2, (by1 - by0) * 2
        if not (40 <= w <= 120 and 40 <= h <= 120 and 0.65 < w / h < 1.45):
            continue
        a0, b0 = max(0, bx0 - 3), max(0, by0 - 3)
        a1, b1 = min(lab.shape[1], bx1 + 3), min(lab.shape[0], by1 + 3)
        ring = blue[b0:b1, a0:a1] & (lab[b0:b1, a0:a1] != L)
        if ring.size and ring.mean() > 0.35:
            return True
    return False


def dedup_candidates(cands, min_dist):
    """同一图标被两种相近颜色切成两个候选时, 只留笔画面积大的那个。
    否则 best 排列可能把两个提示指到同一个位置: 连点两下会被厂商当成撤销/重复,
    真机上就表现为「只标了 1 或 2 个图标」然后停住。"""
    out = []
    for c in sorted(cands, key=lambda t: -t[4]):
        if all(abs(c[1][0] - o[1][0]) + abs(c[1][1] - o[1][1]) >= min_dist for o in out):
            out.append(c)
    return out


def plan_icon(img, d):
    hints = split_hint(img, d["hint"])
    darkp = panel_color(img, d["modal"]).mean() < 95
    photo = d["photo"]
    pw, ph = photo[2] - photo[0], photo[3] - photo[1]
    # 深色图片上沿是大片暗色时 find_photo 只框到下半张 (真机 14:03: 980x448
    # 而不是 980x652), 顶部图标必然漏检。这种帧不能点残缺序列 -> 刷新换图。
    if darkp and ph < 0.58 * pw:
        return None, {"hints": len(hints), "cands": 0, "weak": True, "reason": "photo_truncated"}
    # 已有编号圆标 = 点到一半的残局 (真机 14:39 截图: 标了 1、2 就停住)。
    if darkp and BADGE_CHECK and has_badge(img, photo):
        return None, {"hints": len(hints), "cands": 0, "weak": True, "reason": "already_clicked"}
    # 深色 Geetest 固定 3 个提示图; 只切出 1~2 个时点了也是残缺序列。
    minh = HINT_MIN_DARK if darkp else 2
    if len(hints) < minh:
        return None, {"hints": len(hints), "cands": 0, "weak": True, "reason": "hints_short"}
    cands = dedup_candidates(icon_candidates(img, photo, sd_max=16 if darkp else 10), TAP_MIN_DIST)
    if len(cands) < len(hints):
        # 图标没凑够数: 「这一帧没看清」而不是「不是验证码」 -> 刷新换图重试。
        return None, {"hints": len(hints), "cands": len(cands), "weak": True, "reason": "cands_short"}
    hp = [polar(m) for m, _ in hints]
    cp = [polar(c[0]) for c in cands]
    Sm = np.array([[polar_sim(a, b) for b in cp] for a in hp])
    best = max(itertools.permutations(range(len(cands)), len(hints)),
               key=lambda p: sum(Sm[i, p[i]] for i in range(len(hints))))
    scores = [float(Sm[i, best[i]]) for i in range(len(hints))]
    info = {"hints": len(hints), "cands": len(cands), "scores": [round(s, 3) for s in scores]}
    # 单项下限 + 均值下限: 已点过的图(带编号圆标, fixtures/13_clicked)均值只有 ~0.67, 不能再点。
    # 补充放行规则与 fixtures 依据见 icon_scores_ok()。
    if not icon_scores_ok(scores):
        info.update(weak=True, reason="low_scores")
        return None, info
    pts = [cands[j][1] for j in best]
    for i in range(len(pts)):
        for j in range(i + 1, len(pts)):
            if abs(pts[i][0] - pts[j][0]) + abs(pts[i][1] - pts[j][1]) < TAP_MIN_DIST:
                info.update(weak=True, reason="duplicate_taps")
                return None, info
    return pts, info


# ---------------- 文字点选 (可选 ddddocr, 懒加载) ----------------
_dd = None
_widx = None


def _ddddocr():
    """返回 (det, ocr) 或 None。cv2 缺失时用同目录 shim/ 下的最小替身。"""
    global _dd
    if _dd is None:
        try:
            try:
                import cv2  # noqa: F401
            except ImportError:
                sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "shim"))
            import ddddocr
            import cv2
            t0 = time.time()
            _dd = (ddddocr.DdddOcr(det=True, show_ad=False), ddddocr.DdddOcr(show_ad=False))
            log("word: ddddocr loaded in %.1f s (cv2=%s)" % (time.time() - t0, "shim" if "shim" in (getattr(cv2, "__file__", "") or "") else "opencv"))
        except Exception as e:  # 缺包/模型载入失败 -> unsupported
            log("word: ddddocr unavailable (%s)" % type(e).__name__)
            _dd = False
    return _dd or None


def _word_index(ocr):
    """字符 -> 概率矩阵列号 (概率矩阵的列序就是 get_charset() 的顺序, 缓存避免每次重建)。"""
    global _widx
    if _widx is None:
        _widx = {c: i for i, c in enumerate(ocr.get_charset())}
    return _widx


def _png(im):
    import io
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def word_targets(img, d):
    """题头 OCR -> (目标字列表或 [], 原文)。目标字须都在 OCR 字符集里。无 ddddocr 时 ([], None)。"""
    dd = _ddddocr()
    if dd is None:
        return [], None
    ocr = dd[1]
    x0, y0, x1, _ = d["modal"]
    text = ocr.classification(Image.fromarray(np.ascontiguousarray(img[y0:d["photo"][1], x0:x1])))
    chars = parse_word_targets(text)
    charset = set(ocr.get_charset())
    if any(c not in charset for c in chars):
        chars = []
    return chars, text


def plan_word(img, d):
    """请依次点击【…】: OCR 题头取目标字, ddddocr 检测框 x 每字多角度概率, 取最优联合分配 (同 cnki_captcha)。"""
    dd = _ddddocr()
    if dd is None:
        return None, {"unsupported": "ddddocr"}
    det, ocr = dd
    index = _word_index(ocr)
    chars, text = word_targets(img, d)
    if not chars:
        return None, {"header": text, "not_captcha": True}
    px0, py0, px1, py1 = d["photo"]
    pim = Image.fromarray(np.ascontiguousarray(img[py0:py1, px0:px1]))
    boxes = det.detection(_png(pim))
    if len(boxes) < len(chars):
        return None, {"chars": chars, "boxes": len(boxes), "not_captcha": True}
    Sm = np.zeros((len(chars), len(boxes)))
    for j, (bx0, by0, bx1, by1) in enumerate(boxes):
        crop = pim.crop((max(0, bx0 - 3), max(0, by0 - 3), bx1 + 3, by1 + 3))
        for v in [crop] + [crop.rotate(a, expand=True, fillcolor=(255, 255, 255)) for a in (-40, -25, -12, 12, 25, 40)]:
            r = ocr.classification(v, probability=True)
            mat = np.array([row for step in r["probabilities"] for row in step], dtype=float)
            for i, ch in enumerate(chars):
                Sm[i, j] = max(Sm[i, j], float(mat[:, index[ch]].max()))
    best = max(itertools.permutations(range(len(boxes)), len(chars)),
               key=lambda p: sum(np.log(Sm[i, p[i]] + 1e-9) for i in range(len(chars))))
    scores = [float(Sm[i, best[i]]) for i in range(len(chars))]
    info = {"chars": chars, "scores": [round(s, 3) for s in scores]}
    if min(scores) < 0.05:
        return None, info
    pts = []
    for i in range(len(chars)):
        bx0, by0, bx1, by1 = boxes[best[i]]
        pts.append((px0 + (bx0 + bx1) // 2, py0 + (by0 + by1) // 2))
    return pts, info


WORD_CUES = ("依次点击", "依次點擊", "按顺序点击", "按順序點擊", "顺序点击")


def parse_word_targets(text):
    """只认验证码句式: 「请依次点击【乾 坤 震】」/「请依次点击: 乾坤震」-> ['乾','坤','震']。
    必须有「依次点击」类提示词, 目标 2..5 个汉字; 「点击领取红包」这类普通弹窗返回 []。"""
    t = text or ""
    cue = next((k for k in WORD_CUES if k in t), None)
    if cue is None:
        return []
    t = t[t.index(cue) + len(cue):]
    for a, b in (("【", "】"), ("[", "]")):
        if a in t and b in t[t.index(a) + 1:]:
            t = t[t.index(a) + 1:]
            t = t[:t.index(b)]
            break
    chars = [c for c in t if "\u4e00" <= c <= "\u9fff"]
    return chars if 2 <= len(chars) <= 5 else []


# ---------------- 滑块 (图像闭环; 未经真机验证) ----------------
def _corr_row(img, k):
    """img(h x W) 与核 k(h x w) 在 x 方向的有效互相关 -> 长 W-w+1 (FFT, 无 cv2.matchTemplate)。"""
    sh = (img.shape[0] + k.shape[0], img.shape[1] + k.shape[1])
    r = np.fft.irfft2(np.fft.rfft2(img, sh) * np.conj(np.fft.rfft2(k, sh)), sh)
    return r[0, :img.shape[1] - k.shape[1] + 1]


def slider_gap(band, mask, start):
    """band: 背景灰度条 (高 = 块高 + 8), mask: 拼图块轮廓 (块高 x 块宽), start: 只在块右缘之后找。
    返回 (缺口左缘 x, 置信度); 阴影 + 边缘两条线索, 同 cnki_captcha.slider_target。"""
    band = band.astype(np.float32)
    p = 4
    m = np.pad(mask.astype(bool), p)
    if band.shape[0] != m.shape[0]:
        return None, 0.0
    mw = mask.shape[1]
    mf = m.astype(np.float32)
    ring = (dilate(m, p) & ~m).astype(np.float32)
    # 线索 1: 缺口是块形状的暗/亮区 -> 块内均值与外环均值之差
    shade = np.abs(_corr_row(band, ring / max(ring.sum(), 1)) - _corr_row(band, mf / max(mf.sum(), 1)))
    # 线索 2: 缺口边缘与块轮廓吻合 (梯度幅值 x 轮廓, 按局部能量归一)
    gx = np.zeros_like(band); gy = np.zeros_like(band)
    gx[:, 1:-1] = band[:, 2:] - band[:, :-2]
    gy[1:-1, :] = band[2:, :] - band[:-2, :]
    edge = np.hypot(gx, gy)
    outline = (dilate(m, 1) & ~m).astype(np.float32)
    edg = _corr_row(edge, outline) / (np.sqrt(np.maximum(_corr_row(edge ** 2, np.ones_like(outline)), 0) * outline.sum()) + 1e-6)
    s0 = max(0, start - p)

    def confidence(score):
        s = score.copy()
        s[:s0] = -1
        g = int(np.argmax(s))
        far = np.abs(np.arange(len(s)) - g) > mw * 0.6
        far[:s0] = False
        second = float(s[far].max()) if far.any() else 0.0
        return g, float(s[g]) / max(second, 1e-6)

    g1, c1 = confidence(shade)
    g2, c2 = confidence(edg)
    if abs(g1 - g2) <= 4 and max(c1, c2) >= 1.5:
        return (g1 + g2) // 2 + p, max(c1, c2) * 1.5
    g, c = (g1, c1) if c1 >= c2 else (g2, c2)
    return g + p, c


# ---------------- 输入注入 (仅 worker 用) ----------------
DRY = os.environ.get("CAP_DRYRUN") == "1"   # 测试用: 只记日志, 不注入任何输入


def _guard(what):
    """每次注入前确认主人 (replay.sh / 录制 daemon) 还活着; 主人死了就立刻停手退出。"""
    if not owner_alive():
        log("owner %d gone, abort before %s" % (OWNER, what))
        raise OwnerGone(0)


def tap(x, y):
    _guard("tap")
    if DRY:
        log("dry tap %d %d" % (x, y))
        return
    _sys(["/system/bin/input", "tap", str(int(x)), str(int(y))])


def motion(ev, x, y):
    if ev != "UP":   # 抬起总要发出去, 不能留下一个按住不放的手指
        _guard("motion " + ev)
    if DRY:
        log("dry motion %s %d %d" % (ev, x, y))
        return
    _sys(["/system/bin/input", "motionevent", ev, str(int(x)), str(int(y))])


class Session:
    """一次回放/录制会话里的求解状态。刷新时刻写进 STAMP 文件, 调度器重试时也守住刷新间隔。"""

    def __init__(self):
        self.last_refresh = 0.0
        try:
            self.last_refresh = float(open(STAMP).read().strip()) if STAMP else 0.0
        except (OSError, ValueError):
            pass

    def refresh(self, btn, before_sig=None):
        """点刷新钮并等到厂商真的换了新题再交回。
        btn 由调用方给: 深色页脚的形状检测偶尔选不出唯一刷新钮, 这时复用上一帧
        记住的坐标 (位置固定), 旧版直接 return False 就一下都不刷新了。"""
        if not btn:
            return False
        wait = REFRESH_GAP - (time.time() - self.last_refresh)
        if wait > 0:
            time.sleep(wait)
        log("refresh tap %s" % (btn,))
        tap(*btn)
        self.last_refresh = time.time()
        if STAMP:
            try:
                with open(STAMP, "w") as f:
                    f.write("%.1f\n" % self.last_refresh)
            except OSError:
                pass
        time.sleep(1.5)
        # 换图中间有一两秒空白/加载帧, 甚至旧题还没被替换。必须等「结构在且图片
        # 内容真的变了」才回去规划, 否则会拿旧图再点一遍 / 把空白帧当成功。
        for _ in range(10):
            time.sleep(0.5)
            try:
                im = capture()
                dd = detect(im)
                if dd["kind"] == "none":
                    continue
                sig = photo_sig(im, dd)
                if before_sig is None or sig is None or sig.shape != before_sig.shape \
                        or np.abs(sig - before_sig).mean() > 12:
                    break
            except Exception:
                pass
        return True

    def solve(self, d, refresh_max=None, budget=None):
        """持续求解: 直到验证码真的消失才返回 solved, 否则一路刷新换图重试。
        status: solved | fail (预算/次数用尽或厂商锁不退) | skip (不是验证码或不支持)。
        图标没凑齐、分数不够、点到一半、答错 -> 都不点残缺序列, 一律换图重来;
        只有「真正提交过 + 连续两帧无验证码」才算成功, 换图空白帧绝不算。
        refresh_max/budget 供录制模式传短预算, 回放默认用全局 8 次 / 240 s。"""
        rmax = REFRESH_MAX if refresh_max is None else refresh_max
        deadline = time.time() + (SOLVE_BUDGET if budget is None else budget)
        last_refresh = d.get("refresh")
        last_confirm = d.get("confirm")
        refreshes = 0
        locks = 0
        tapped = False
        attempt = 0
        while attempt < rmax + 1 and time.time() < deadline:
            attempt += 1
            t0 = time.time()
            img = capture()
            d = detect(img)
            if d.get("refresh"):
                last_refresh = d["refresh"]
            if d.get("confirm"):
                last_confirm = d["confirm"]
            if d["kind"] == "locked":
                locks += 1
                if locks > LOCK_MAX:
                    return "fail", "vendor lock persists after %d cooldowns" % (locks - 1)
                log("vendor 'too many attempts' lock, cool down %.0f s then retry (%d/%d)" %
                    (LOCK_WAIT, locks, LOCK_MAX))
                time.sleep(LOCK_WAIT)
                if last_refresh:
                    tap(*last_refresh)
                continue
            if d["kind"] == "none":
                # 换图/关闭动画的单帧空白不算结束 (真机曾因此 solved gone -> 提前锁屏)
                time.sleep(0.6)
                if detect(capture())["kind"] != "none":
                    continue
                if tapped:
                    return "solved", "gone"
                return "skip", "gone with no submit" if refreshes else "gone before solving"
            kind = d["kind"]
            if kind == "slider":
                tapped = True
                ok, why = self.slide(img, d)
                log("slider attempt %d: %s" % (attempt, why))
                if ok is True:
                    return "solved", "slider (attempt %d)" % attempt
                if ok == "fail":
                    return "fail", why
            else:
                pts, info = plan_icon(img, d) if kind == "icon" else plan_word(img, d)
                log("%s plan %s pts=%s (%.0f ms)" %
                    (kind, json.dumps(info, ensure_ascii=False), pts, (time.time() - t0) * 1000))
                if info.get("unsupported"):
                    return "skip", "unsupported:%s(%s)" % (kind, info["unsupported"])
                if info.get("not_captcha") and not tapped:
                    # word: 题头没有「依次点击」句式 -> 普通弹窗, 一下都不点也不刷新
                    return "skip", "%s: not a captcha (%s)" % (kind, ",".join(sorted(k for k in info if k != "not_captcha")))
                if info.get("weak"):
                    reason = info.get("reason", "icons unresolved")
                    log("%s: %s (%d icons / %d hints) -> refresh, no partial taps" %
                        (kind, reason, info.get("cands", 0), info.get("hints", 0)))
                if pts:
                    for (x, y) in pts:
                        tap(x, y)
                        time.sleep(TAP_GAP)
                    btn = d.get("confirm") or last_confirm
                    if btn:
                        tap(*btn)
                    tapped = True
                    res = self.gone(GONE_WAIT)
                    if res is True:
                        return "solved", "%s (attempt %d)" % (kind, attempt)
                    if res:
                        # 提交后弹出厂商锁: 冷却再战, 不直接判失败
                        locks += 1
                        log("submit: %s -> cool down (%d/%d)" % (res, locks, LOCK_MAX))
                        if locks > LOCK_MAX:
                            return "fail", "vendor lock persists after submit"
                        time.sleep(LOCK_WAIT)
                        if last_refresh:
                            tap(*last_refresh)
                        continue
                    log("%s: still present after submit, refresh & retry" % kind)
            if attempt > rmax or time.time() >= deadline:
                break
            # 提交/放弃后先确认不是「慢一拍的成功」; 仍在就一律换图 ——
            # 带编号圆标、错误提示或答错的旧题绝不能拿来继续点。
            time.sleep(1.0)
            img2 = capture()
            d2 = detect(img2)
            if d2["kind"] == "locked":
                continue                      # 下一轮循环顶部按厂商锁冷却处理, 别在锁弹窗上乱点
            if d2["kind"] == "none":
                time.sleep(0.6)
                if detect(capture())["kind"] == "none":
                    if tapped:
                        return "solved", "gone"
                    continue
            btn = d2.get("refresh") or last_refresh
            before = photo_sig(img2, d2)
            if before is None:
                before = photo_sig(img, d)
            refreshes += 1
            if not self.refresh(btn, before):
                time.sleep(REFRESH_GAP)   # 连缓存坐标都没有: 等厂商自动换图
        return "fail", "unsolved after %d refreshes / %d attempts" % (refreshes, attempt)

    def gone(self, wait):
        """提交后: True = 验证码消失(含无图成功确认弹窗); False = 还在; 字符串 = 失败原因 (厂商锁)。"""
        end = time.time() + wait
        while True:
            time.sleep(0.6)
            d = detect(capture())
            if d["kind"] == "locked":
                return "locked: vendor 'too many attempts' dialog after submit"
            if d["kind"] == "none":
                # 连续两帧确认: 换图/关闭动画的单帧空白不能算已解决。
                time.sleep(0.6)
                d2 = detect(capture())
                if d2["kind"] != "none":
                    if time.time() > end:
                        return False
                    continue
                # 提交后验证码已消失。此时可能还有一层无图弹窗 —— 实测是签到成功的
                # 确认框 (画面最终停在成功页), 而非失败: 厂商锁是 locked 且在上面先拦,
                # 解错时验证码仍会留在屏上走刷新重试。这里按成功收尾。
                if d.get("modal"):
                    log("picture-less dialog after submit treated as success")
                return True
            if time.time() > end:
                return False

    def slide(self, img0, d):
        """按住滑钮先挪 30 px, 两帧差分得拼图块, 找缺口, 分段拖到位并截图校正。未经真机验证。
        返回 (True|False|"fail", 说明)。"""
        hx, hy = d["handle"]
        px0, py0, px1, py1 = d["photo"]
        A = img0[py0:py1, px0:px1].astype(np.int16)
        pos = 0
        motion("DOWN", hx, hy)
        try:
            for k in (10, 20, 30):
                motion("MOVE", hx + k, hy)
            pos = 30
            time.sleep(0.3)
            B = capture()[py0:py1, px0:px1].astype(np.int16)
            D = np.abs(A - B).sum(2) > 60
            ys, xs = np.nonzero(D)
            if len(ys) < 200:
                return False, "piece did not move"
            r0, r1 = int(ys.min()), int(ys.max()) + 1
            a, b = int(xs.min()), int(xs.max()) + 1
            if b - a - pos < 10:
                return False, "piece too small"
            mask = D[r0:r1, a:b - pos]
            q0, q1 = r0 - 4, r1 + 4
            if q0 < 0 or q1 > A.shape[0]:
                return False, "piece at photo edge"
            gx, conf = slider_gap(A[q0:q1].mean(2), mask, b - pos)
            if gx is None or conf < 1.3:
                return False, "gap confidence %.2f" % conf
            need = gx - a
            log("slider: piece x=%d gap x=%d conf=%.2f" % (a, gx, conf))
            target = need
            for _ in range(4):
                n = max(2, int(abs(target - pos) // 30))
                for i in range(1, n + 1):
                    motion("MOVE", hx + pos + (target - pos) * i / n, hy + (i % 2))
                pos = target
                time.sleep(0.25)
                C = capture()[py0 + r0:py0 + r1, px0:px1].astype(np.int16)
                cols = np.nonzero((np.abs(C - A[r0:r1]).sum(2) > 60).any(0))[0]
                if not len(cols):
                    break
                moved = int(cols.max()) + 1 - (b - 30)   # 块右缘相对原位的位移
                err = need - moved
                if abs(err) <= 3:
                    break
                target = pos + err   # 滑钮与块不是 1:1 时按实测补偿
        finally:
            motion("UP", hx + pos, hy)
        res = self.gone(3.0)
        if res is True:
            return True, "released at +%d" % pos
        return ("fail", res) if res else (False, "still present after release")


class Throttle:
    """同一类日志 60 s 内只记一次 (持续性错误不刷屏)。"""

    def __init__(self, gap=60.0):
        self.gap, self.last = gap, {}

    def __call__(self, key, msg):
        now = time.time()
        if now - self.last.get(key, 0) >= self.gap:
            self.last[key] = now
            log(msg)


def record_loop(ses, flag, idle):
    """录制: 截屏检测。画面不变/录制暂停 (daemon 建 idle 标记) 时退避到 3 s, 出错同样退避且日志限频。

    默认不建 captcha.on 闸门: 求解器用 /system/bin/input 注入, 不进 getevent 硬件流,
    而 record.sh 的 CAPGATE 看到 flag 会丢弃期间**所有用户手势**。旧版单帧误报就吞掉
    整段录制; 新版 solve() 又变成 8 次刷新/240 s 长循环, 闸门全程存在, 真机 15:47-15:49
    四次录制全部 READY 后立刻 Empty。现在求解后台跑、双帧确认防乱刷、录制不中断。
    CAP_RECORD_GATE=1 可恢复旧闸门行为。
    """
    say = Throttle()
    interval, prev = 0.7, None
    cooldown = 0.0
    while owner_alive():
        t0 = time.time()
        d = {"kind": "none"}
        if idle and os.path.exists(idle):
            interval = 3.0
        else:
            try:
                img = capture()
                sig = img[::16, ::16].astype(np.int16)
                same = prev is not None and sig.shape == prev.shape and np.abs(sig - prev).mean() < 1.5
                prev = sig
                d = detect(img)
                interval = min(3.0, interval * 1.5) if same and d["kind"] == "none" else 0.7
            except Exception as e:
                say("err", "record check error %s: %s (retrying every 3 s)" % (type(e).__name__, e))
                interval = 3.0
        if d["kind"] == "word":
            chars = word_targets(img, d)[0] if _ddddocr() is not None else []
            if not chars:   # 未经题头句式确认的文字点选候选: 不暂停、不点
                say("word", "record: picture dialog without click-word prompt -> ignored")
                d = {"kind": "none"}
        if d["kind"] != "none" and time.time() >= cooldown:
            # 双帧确认: 0.35 s 后复查, 两帧同类型才算真有验证码。单帧误报不建 flag,
            # 否则「触发验证码的那一下」以及随后所有手势都会被 CAPGATE 丢掉。
            time.sleep(0.35)
            try:
                d2 = detect(capture())
            except Exception:
                d2 = {"kind": "none"}
            if d2["kind"] != d["kind"]:
                log("record: %s not confirmed on 2nd frame -> ignored (transient)" % d["kind"])
                cooldown = time.time() + 0.8
                interval, prev = 0.7, None
                time.sleep(max(0.1, interval - (time.time() - t0)))
                continue
            if RECORD_GATE:
                open(flag, "w").close()
            log("record: %s detected, solving in background%s" %
                (d["kind"], " (recording paused)" if RECORD_GATE else " (recording continues)"))
            # 录制窗口只有几十秒, 给短预算让求解能走完并给出结论; 回放仍用 8 次/240 s。
            try:
                st, why = ses.solve(d, refresh_max=RECORD_REFRESH_MAX,
                                    budget=RECORD_SOLVE_BUDGET)
            except OwnerGone:
                raise
            except Exception as e:
                st, why = "fail", "solve error %s: %s" % (type(e).__name__, e)
            log("record: %s %s" % (st, why))
            if RECORD_GATE and os.path.exists(flag):
                os.remove(flag)
            log("record: captcha done (%s)" % st)
            cooldown = time.time() + 1.2
            interval, prev = 0.7, None
        time.sleep(max(0.1, interval - (time.time() - t0)))


def worker(mode, owner, fin, fout, flag):
    global OWNER
    import signal
    signal.signal(signal.SIGTERM, lambda *a: sys.exit(0))   # 让 finally 删掉 flag 并记下退出
    OWNER = int(owner)
    t0 = time.time()
    pick_display()
    log("worker start mode=%s owner=%s py=%s display=%s (%.0f ms)" % (mode, owner, sys.version.split()[0], DISPLAY or "default", (time.time() - t0) * 1000))
    ses = Session()
    try:
        if mode == "record":
            record_loop(ses, flag, os.environ.get("CAP_IDLE", ""))
            return
        rfd = os.open(fin, os.O_RDONLY | os.O_NONBLOCK)
        out = open(fout, "w")
        buf = b""
        while True:
            r, _, _ = select.select([rfd], [], [], 2.0)
            if not owner_alive():
                break
            if not r:
                continue
            chunk = os.read(rfd, 4096)
            if not chunk:
                time.sleep(0.2)   # 暂无写端; 主人还活着就继续等
                continue
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if line.strip() == b"quit":
                    return
                t0 = time.time()
                try:
                    d = detect(capture())
                    if d["kind"] == "none":
                        st, why = "none", "-"
                    else:
                        # 厂商「尝试过多」锁也交给 solve(): 它会冷却后继续换图重试,
                        # 旧版在这里直接判 fail, 回放立刻 rc=4 收工。
                        log("replay: %s captcha detected" % d["kind"])
                        st, why = ses.solve(d)
                        log("replay: %s %s" % (st, why))
                except OwnerGone:
                    raise
                except Exception as e:
                    st, why = "error", type(e).__name__ + ":" + str(e).replace("\n", " ")[:100]
                    log("replay: error %s" % why)
                out.write("%s %d %s\n" % (st, int((time.time() - t0) * 1000), why.replace(" ", "_")))
                out.flush()
    finally:
        if flag and os.path.exists(flag):
            os.remove(flag)
        log("worker exit mode=%s" % mode)


def main(argv):
    if len(argv) >= 2 and argv[0] == "detect":
        t0 = time.time()
        img = load(argv[1])
        t1 = time.time()
        d = detect(img)
        res = {"kind": d["kind"], "load_ms": int((t1 - t0) * 1000)}
        if d["kind"] == "icon":
            pts, info = plan_icon(img, d)
            res.update(pts=pts, info=info, confirm=d.get("confirm"), refresh=d.get("refresh"))
        elif d["kind"] == "word" and "--ocr" in argv:
            pts, info = plan_word(img, d)
            res.update(pts=pts, info=info)
        res["ms"] = int((time.time() - t1) * 1000)
        print(json.dumps(res, ensure_ascii=False))
        return 0
    if len(argv) >= 6 and argv[0] == "worker":
        worker(argv[1], argv[2], argv[3], argv[4], argv[5])
        return 0
    print("usage: capsolve.py detect IMG [--ocr] | worker replay|record OWNER_PID FIFO_IN FIFO_OUT FLAG", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
