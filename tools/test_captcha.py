# 离线验证码求解测试 (PC 或手机 Termux 均可跑; 不截屏、不注入任何输入)
#   python tools/test_captcha.py [FIXTURE_DIR]
# 1) 真机截图: 图标点选的点击位置/顺序, 负样本不误报, 已点过的图不再规划
# 2) 合成图: 连通域、raw screencap 解析、文字点选题头解析与结构识别、滑块缺口定位
# 3) 可选: 装了 ddddocr 时跑文字点选端到端 (真 cv2 / cv2 替身各一次)
import json, os, struct, subprocess, sys, time

sys.dont_write_bytecode = True   # 不在 captcha/ 里留 __pycache__
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "captcha"))
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # noqa: E402
import capsolve as C  # noqa: E402

FX = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".agent", "fixtures")
fails = 0


def check(ok, msg):
    global fails
    print(("  ok   " if ok else "  FAIL ") + msg)
    if not ok:
        fails += 1


def near(p, q, tol):
    return p is not None and ((p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2) ** 0.5 <= tol


# ---------- 1. 真机截图 ----------
lab_path = os.path.join(FX, "labels.json")
if os.path.exists(lab_path):
    L = json.load(open(lab_path, encoding="utf-8"))
    tol = L["tol"]
    print("== fixtures (%s)" % FX)
    times = []
    for name, want in L["icon"].items():
        img = C.load(os.path.join(FX, name))
        t0 = time.time()
        d = C.detect(img)
        pts, info = C.plan_icon(img, d) if d["kind"] == "icon" else (None, {})
        dt = (time.time() - t0) * 1000
        times.append(dt)
        good = d["kind"] == "icon" and pts is not None and len(pts) == len(want) and all(near(p, q, tol) for p, q in zip(pts, want))
        check(good, "%s icon %s scores=%s (%.0f ms)" % (name, pts, info.get("scores"), dt))
        check(near(d.get("confirm"), L["buttons"]["confirm"], 30) and near(d.get("refresh"), L["buttons"]["refresh"], 30),
              "%s buttons confirm=%s refresh=%s" % (name, d.get("confirm"), d.get("refresh")))
    for name in L["none"]:
        img = C.load(os.path.join(FX, name))
        t0 = time.time()
        d = C.detect(img)
        check(d["kind"] == "none", "%s -> %s (%.0f ms, no captcha expected)" % (name, d["kind"], (time.time() - t0) * 1000))
    for name in L.get("locked", []):
        img = C.load(os.path.join(FX, name))
        d = C.detect(img)
        check(d["kind"] == "locked", "%s -> locked (vendor rate-limit dialog)" % name)
    for name in L["no_plan"]:
        img = C.load(os.path.join(FX, name))
        d = C.detect(img)
        pts, info = C.plan_icon(img, d) if d["kind"] == "icon" else (None, {})
        check(pts is None, "%s -> no new taps on an already-clicked picture (scores=%s)" % (name, info.get("scores")))
    print("  icon solve time: mean %.0f ms, max %.0f ms" % (sum(times) / len(times), max(times)))

    # Session.solve 的流程 (截屏/点击/睡眠全打桩, 不碰真机)
    tapt = []

    def run_session(frames_after_taps, first):
        taps, sleeps = [], []
        del tapt[:]
        state = {"img": C.load(os.path.join(FX, first)), "n": 0}
        seq = [C.load(os.path.join(FX, f)) for f in frames_after_taps]
        orig = (C.capture, C.tap, C.time.sleep, C.time.time)
        C.capture = lambda: state["img"]
        real = C.time.time
        vclock = lambda: real() + sum(sleeps)   # 虚拟时钟 = 真实耗时 + 打桩掉的睡眠

        def fake_tap(x, y):
            taps.append((int(x), int(y)))
            tapt.append(vclock())
            if near((x, y), L["buttons"]["confirm"], 30):   # 点「确认」后换到下一帧
                state["img"] = seq[min(state["n"], len(seq) - 1)]
                state["n"] += 1
        C.tap = fake_tap
        C.time.sleep = lambda s: sleeps.append(s)   # 不真睡, 记下要睡多久
        C.time.time = vclock
        try:
            return C.Session().solve(C.detect(state["img"])), taps, sleeps
        finally:
            C.capture, C.tap, C.time.sleep, C.time.time = orig

    (st, why), taps, sl = run_session(["xmsq_icon_13_after.png"], "xmsq_icon_13.png")
    want = L["icon"]["xmsq_icon_13.png"]
    check(st == "solved" and len(taps) == 4 and all(near(p, q, tol) for p, q in zip(taps, want)) and near(taps[3], L["buttons"]["confirm"], 30),
          "Session: 13 -> 3 icon taps + confirm -> gone => %s %s taps=%s" % (st, why, taps))
    check(sum(1 for s in sl if abs(s - C.TAP_GAP) < 1e-6) >= 3, "Session: %.1f s between icon taps" % C.TAP_GAP)
    (st, why), taps, sl = run_session(["xmsq_icon_13_clicked.png"], "xmsq_icon_13_clicked.png")
    refresh = [t for t in taps if near(t, L["buttons"]["refresh"], 30)]
    check(st == "fail" and len(refresh) == C.REFRESH_MAX and len(taps) == C.REFRESH_MAX,
          "Session: never-solvable picture -> %s after %d refresh taps (cap %d), no icon taps" % (st, len(refresh), C.REFRESH_MAX))
    gaps = [b - a for a, b in zip(tapt, tapt[1:])]
    check(len(gaps) == C.REFRESH_MAX - 1 and min(gaps) >= C.REFRESH_GAP - 0.01,
          "Session: refresh taps spaced %s s (>= %.1f, vendor rate limit)" % ([round(g, 1) for g in gaps], C.REFRESH_GAP))

    # review M2: 厂商「尝试过多」锁弹窗必须算失败, 不许当成已解决
    lock_img = C.load(os.path.join(FX, "xmsq_icon_7_toomany.png"))
    dl = C.detect(lock_img)
    taps2 = []
    orig = (C.capture, C.tap, C.time.sleep)
    C.capture = lambda: lock_img
    C.tap = lambda x, y: taps2.append((int(x), int(y)))
    C.time.sleep = lambda s: None
    try:
        stl, whyl = C.Session().solve(dl)
    finally:
        C.capture, C.tap, C.time.sleep = orig
    check(dl["kind"] == "locked" and stl == "fail" and not taps2,
          "Session: vendor 'too many attempts' dialog -> kind=%s solve=%s (%s) taps=%s" % (dl["kind"], stl, whyl, taps2))
else:
    print("== fixtures skipped (no %s)" % lab_path)

# ---------- 2. 合成单元测试 ----------
print("== synthetic")
m = np.zeros((6, 8), bool)
m[0, 0:2] = m[1, 2] = True        # 斜向相连 -> 1 个
m[4:6, 5:8] = True                # 另一个
lab, boxes = C.components(m)
check(len(boxes) == 2 and sorted(b[4] for b in boxes) == [3, 6], "components 8-connectivity %s" % boxes)

raw = struct.pack("<IIII", 120, 110, 1, 0) + bytes(np.full((110, 120, 4), 7, np.uint8))
check(C.from_raw(raw).shape == (110, 120, 3), "raw screencap parse (16-byte header)")

check(C.parse_word_targets("请依次点击【乾 坤 震】") == ["乾", "坤", "震"], "parse 【…】 targets")
check(C.parse_word_targets("请依次点击：山水云") == ["山", "水", "云"], "parse colon targets")
check(C.parse_word_targets("立即签到") == [], "parse: no targets on unrelated text")


def font(sz):
    for f in ("C:/Windows/Fonts/simhei.ttf", "/system/fonts/NotoSansCJK-Regular.ttc", "/system/fonts/MiSansVF.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return None


def synth_word(chars="山水云", decoy="木"):
    """暗色遮罩 + 白弹窗 + 黑字题头 + 图片上散布旋转汉字。返回 (截图, 各目标字中心)。"""
    rng = np.random.default_rng(1)
    W, H = 1220, 2656
    scr = np.full((H, W, 3), 12, np.uint8)
    scr[660:1990, 96:1128] = 255
    x0, y0, x1, y1 = 116, 826, 1106, 1818
    yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
    photo = np.stack([90 + 60 * np.sin(xx / 90.0), 120 + 50 * np.cos(yy / 70.0), 100 + 0 * xx], 2)
    photo += rng.normal(0, 18, photo.shape)
    scr[y0:y1, x0:x1] = np.clip(photo, 0, 255).astype(np.uint8)
    im = Image.fromarray(scr)
    f = font(56)
    if f is None:
        return None, None
    ImageDraw.Draw(im).text((130, 710), "请依次点击【%s】" % " ".join(chars), font=font(44), fill=(0, 0, 0))
    centers = []
    spots = [(260, 1050), (780, 1000), (420, 1500), (860, 1560)]
    for i, (ch, (cx, cy)) in enumerate(zip(chars + decoy, spots)):
        g = Image.new("L", (110, 110), 0)
        ImageDraw.Draw(g).text((25, 20), ch, font=f, fill=255)
        g = g.rotate([-25, 15, 30, -10][i], resample=Image.BILINEAR)
        col = [(250, 230, 60), (255, 90, 60), (80, 240, 250), (240, 120, 250)][i]
        im.paste(Image.new("RGB", g.size, col), (cx - 55, cy - 55), g)
        if i < len(chars):
            centers.append((cx, cy))
    dr = ImageDraw.Draw(im)
    dr.rounded_rectangle((760, 1860, 1090, 1940), 40, fill=(140, 180, 245))   # 确认钮
    dr.ellipse((280, 1860, 350, 1930), outline=(120, 120, 120), width=6)      # 关闭
    dr.arc((380, 1865, 450, 1935), 30, 200, fill=(120, 120, 120), width=6)    # 刷新 (上弧)
    dr.arc((380, 1865, 450, 1935), 210, 380, fill=(120, 120, 120), width=6)   # 刷新 (下弧)
    return np.asarray(im), centers


wimg, wcent = synth_word()
if wimg is None:
    print("  skip word synthetic (no CJK font)")
else:
    d = C.detect(wimg)
    check(d["kind"] == "word", "synthetic click-word screen -> kind=%s" % d["kind"])


def synth_dialog(header, with_banner=False, with_photo=True):
    """普通弹窗 (非验证码): 暗底 + 白弹窗 + 题头文字 + 可选横幅条 + 大图片 + 蓝色主按钮 + 灰色小图标。"""
    W, H = 1220, 2656
    scr = np.full((H, W, 3), 12, np.uint8)
    scr[660:1990, 96:1128] = 255
    x0, y0, x1, y1 = 116, 826, 1106, 1818
    yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
    rng = np.random.default_rng(2)
    photo = np.stack([90 + 60 * np.sin(xx / 90.0), 120 + 50 * np.cos(yy / 70.0), 100 + 0 * xx], 2)
    photo += rng.normal(0, 18, photo.shape)
    scr[y0:y1, x0:x1] = np.clip(photo, 0, 255).astype(np.uint8)
    im = Image.fromarray(scr)
    dr = ImageDraw.Draw(im)
    if with_photo:
        dr.text((130, 710), header, font=font(44), fill=(0, 0, 0))
    if with_banner:
        # 横幅条: 非白、填充率高、带几个墨迹块 (普通弹窗常见, 不该被当成提示图)
        by0, by1 = 690, 800
        dr.rectangle((130, by0, 1090, by1), fill=(235, 90, 60))
        for cx in (260, 480, 700):
            dr.ellipse((cx - 30, by0 + 15, cx + 30, by1 - 15), fill=(40, 40, 40))
    # 蓝色主按钮 (右侧) + 灰色小图标 (左下)
    dr.rounded_rectangle((760, 1860, 1090, 1940), 40, fill=(140, 180, 245))
    dr.ellipse((280, 1860, 350, 1930), outline=(120, 120, 120), width=6)
    return np.asarray(im)


for header, banner, name in (("点击领取红包", False, "redpacket"), ("新版本上线", True, "banner")):
    dim = synth_dialog(header, with_banner=banner)
    dd2 = C.detect(dim)
    taps3 = []
    orig = (C.capture, C.tap, C.time.sleep)
    C.capture = lambda: dim
    C.tap = lambda x, y: taps3.append((int(x), int(y)))
    C.time.sleep = lambda s: None
    try:
        std, whyd = C.Session().solve(dd2)
    finally:
        C.capture, C.tap, C.time.sleep = orig
    check(std == "skip" and not taps3,
          "%s dialog -> kind=%s solve=%s (%s) taps=%s (must not act)" % (name, dd2["kind"], std, whyd, taps3))


def synth_slider(gap_x=230, piece_x=12, shade=-55):
    """背景条 + 拼图形缺口 (暗) + 左侧块 (亮边)。返回 (灰度条(块高+8), 块掩码, 块右缘)。"""
    rng = np.random.default_rng(3)
    h, w = 80, 400
    yy, xx = np.mgrid[0:h, 0:w]
    bg = 120 + 40 * np.sin(xx / 23.0) + 30 * np.cos(yy / 11.0) + rng.normal(0, 6, (h, w))
    mask = np.zeros((60, 60), bool)
    mask[8:52, 8:52] = True
    yy2, xx2 = np.mgrid[0:60, 0:60]
    mask |= (xx2 - 30) ** 2 + (yy2 - 6) ** 2 < 64       # 上凸耳
    mask &= ~(((xx2 - 52) ** 2 + (yy2 - 30) ** 2) < 49)  # 右凹口
    top = 10
    reg = bg[top:top + 60, gap_x:gap_x + 60]
    reg[mask] += shade
    piece = bg[top:top + 60, gap_x:gap_x + 60].copy()
    bg[top:top + 60, piece_x:piece_x + 60][mask] = piece[mask] + 40
    band = bg[top - 4:top + 64]
    return band, mask, piece_x + 60


for gx in (150, 230, 310):
    band, mask, start = synth_slider(gap_x=gx)
    x, conf = C.slider_gap(band, mask, start)
    check(x is not None and abs(x - gx) <= 3 and conf >= 1.3, "slider_gap synthetic gap=%d -> %s conf=%.2f" % (gx, x, conf))

# ---------- 3. 可选: ddddocr 文字点选端到端 ----------
try:
    import ddddocr  # noqa: F401
    have_dd = True
except Exception:
    have_dd = False
if not have_dd or wimg is None:
    print("== word end-to-end skipped (ddddocr not importable here)")
else:
    print("== word end-to-end (ddddocr)")
    d = C.detect(wimg)
    t0 = time.time()
    pts, info = C.plan_word(wimg, d)
    dt = (time.time() - t0) * 1000
    ok = pts is not None and all(near(p, q, 60) for p, q in zip(pts, wcent))
    # 合成图仅作冒烟测试: 只报告, 不计失败 (ddddocr 在合成字上的命中不代表真验证码)
    print("  %s synthetic word plan pts=%s info=%s (%.0f ms, real cv2)" % ("ok  " if ok else "info", pts, info, dt))
    shim = os.path.join(ROOT, "captcha", "shim")
    code = ("import sys; sys.path.insert(0, %r); import cv2; assert cv2.__file__.startswith(%r);"
            "from ddddocr.core import detection_engine; import numpy as np, io; from PIL import Image;"
            "im = Image.new('RGB', (64, 48), (200, 10, 10)); b = io.BytesIO(); im.save(b, 'PNG');"
            "a = cv2.imdecode(np.frombuffer(b.getvalue(), np.uint8), cv2.IMREAD_COLOR);"
            "assert a.shape == (48, 64, 3) and tuple(a[0, 0]) == (10, 10, 200), a[0, 0];"
            "r = cv2.resize(a, (32, 24), interpolation=cv2.INTER_LINEAR); assert r.shape == (24, 32, 3);"
            "print('shim ok')") % (shim, shim)
    r = subprocess.run([sys.executable, "-B", "-c", code], capture_output=True, text=True)
    check(r.returncode == 0 and "shim ok" in r.stdout, "cv2 shim imdecode/resize + ddddocr detection_engine import (%s)" % (r.stderr.strip()[-120:] or "-"))
    # 同一张合成图走 cv2 替身 (PYTHONPATH 让 shim 先于真 cv2), 结果应与真 cv2 一致
    tmp = os.path.join(os.environ.get("TMPDIR") or os.environ.get("TEMP") or "/data/local/tmp", "cap_word_synth.png")
    Image.fromarray(wimg).save(tmp)
    env = dict(os.environ, PYTHONPATH=shim, PYTHONUTF8="1", PYTHONDONTWRITEBYTECODE="1")
    t0 = time.time()
    r = subprocess.run([sys.executable, os.path.join(ROOT, "captcha", "capsolve.py"), "detect", tmp, "--ocr"], capture_output=True, text=True, env=env)
    try:
        sp = json.loads(r.stdout.strip().splitlines()[-1]).get("pts")
    except Exception:
        sp = None
    same = sp is not None and pts is not None and all(near(p, q, 5) for p, q in zip(sp, pts))
    check(same, "word plan via cv2 shim == real cv2: %s (%.0f ms incl. model load) %s" % (sp, (time.time() - t0) * 1000, r.stderr.strip()[-160:]))
    os.remove(tmp)

print("== %s" % ("ALL PASS" if fails == 0 else "%d FAIL" % fails))
sys.exit(1 if fails else 0)
