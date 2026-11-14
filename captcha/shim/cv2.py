# 最小 cv2 替身: 只给 ddddocr 1.6.1 检测/OCR 路径用 (detection_engine 里的 imdecode/resize)。
# Termux 主仓没有 OpenCV (x11-repo 的要拖 ~800 MB 依赖), 文字点选只需要这两个函数。
# 其它属性一律报错, 不让意外的 OpenCV 调用静默出错。capsolve.py 仅在真 cv2 缺失时把本目录加入 sys.path。
import io

import numpy as np
from PIL import Image

INTER_LINEAR = 1
IMREAD_COLOR = 1


def imdecode(buf, flags=IMREAD_COLOR):
    try:
        im = Image.open(io.BytesIO(np.asarray(buf, np.uint8).tobytes())).convert("RGB")
    except Exception:
        return None
    return np.ascontiguousarray(np.asarray(im)[..., ::-1])   # OpenCV 约定 BGR


def resize(img, dsize, interpolation=INTER_LINEAR):
    w, h = int(dsize[0]), int(dsize[1])
    return np.asarray(Image.fromarray(np.ascontiguousarray(img)).resize((w, h), Image.BILINEAR))


def __getattr__(name):
    raise AttributeError("cv2 shim: %s not provided (only imdecode/resize)" % name)
