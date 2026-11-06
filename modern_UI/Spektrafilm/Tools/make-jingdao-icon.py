#!/usr/bin/env python3
"""景到 图标：小孔成像。

《墨子·经下》：“景到，在午有端，与景长，说在端。”
—— 景到：像是倒的；在午：光线交叉；有端：交叉于一点（小孔）。

几何：左边是“物”（橙色旗杆与三角旗），右边是“像”，等于“物”绕小孔 C 中心对称
（上下左右俱倒）。橙色光线从物的旗面经小孔到像的旗面；米白光锥从物的底部经小孔
到像的顶部。构图取自用户认可的概念稿，按几何关系精确重画，不含任何第三方标识。

用法：python3 Tools/make-jingdao-icon.py 输出.png [输出.svg]
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4                                   # 超采样倍数，抗锯齿
C = (512.0, 512.0)                       # 小孔（端）
BODY = (100, 100, 924, 924)              # macOS 图标网格：824×824 主体
RADIUS = 186
GROUND_TOP, GROUND_BOTTOM = (40, 40, 42), (22, 22, 24)
ORANGE = (255, 90, 20)
CREAM = (255, 248, 238)

# “物”（左）：旗杆与三角旗
L, W, T, B = 172, 80, 270, 700           # 旗杆：左、宽、上、下
FLAG_H = 106
FLAG_TIP = (L + 262, T + FLAG_H)
_slope = FLAG_H / 262                    # 旗面上沿与杆顶连成一条斜线
FLAG = [(L, T), FLAG_TIP, (L + W, T + FLAG_H)]
POLE = [(L, T), (L + W, T + W * _slope), (L + W, B), (L, B)]
POLE_HEAD = [(L, T), (L + W, T + W * _slope), (L + W, T + FLAG_H), (L, T + FLAG_H)]  # 挂旗那一段
# 米白光锥：从物的底部收向小孔（宽端 56，小孔处 14）
CONE_LEFT = [(L, B - 6), (L, B + 50), (C[0], C[1] + 7), (C[0], C[1] - 7)]
RAY_W = 24                               # 橙色光线宽度（小尺寸下仍可见）
DOT_R, RING = 40, 9                      # 小孔：米白圆点 + 橙色细环


def mirror(pts):
    """绕小孔中心对称：上下左右俱倒。"""
    return [(2 * C[0] - x, 2 * C[1] - y) for x, y in pts]


def band(p, q, w):
    dx, dy = q[0] - p[0], q[1] - p[1]
    n = math.hypot(dx, dy)
    ox, oy = -dy / n * w / 2, dx / n * w / 2
    return [(p[0] + ox, p[1] + oy), (q[0] + ox, q[1] + oy), (q[0] - ox, q[1] - oy), (p[0] - ox, p[1] - oy)]


FLAG_FOOT = (L + W, T + FLAG_H)          # 旗面与旗杆的交点
SHAPES = [   # (颜色, 多边形)，按绘制顺序
    (CREAM, CONE_LEFT), (CREAM, mirror(CONE_LEFT)),
    (ORANGE, band(FLAG_FOOT, mirror([FLAG_FOOT])[0], RAY_W)),
    (ORANGE, POLE), (ORANGE, FLAG),
    # 像：杆身是米白的光，挂旗那一段与旗同为橙色——旗在像里落到了最下面
    (CREAM, mirror(POLE)), (ORANGE, mirror(POLE_HEAD)), (ORANGE, mirror(FLAG)),
]


def render_png(out):
    S = SIZE * SS
    sc = lambda pts: [(x * SS, y * SS) for x, y in pts]
    canvas = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # 投影：主体下方柔和阴影
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle(
        [v * SS for v in (BODY[0], BODY[1] + 12, BODY[2], BODY[3] + 12)], radius=RADIUS * SS, fill=(0, 0, 0, 110))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18 * SS)))
    # 主体：自上而下的轻微渐变
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    y0, y1 = BODY[1] * SS, BODY[3] * SS
    for y in range(y0, y1):
        t = (y - y0) / (y1 - y0)
        gd.line([(0, y), (S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(GROUND_TOP, GROUND_BOTTOM)) + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([v * SS for v in BODY], radius=RADIUS * SS, fill=255)
    canvas.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(canvas)
    for color, pts in SHAPES:
        d.polygon(sc(pts), fill=color + (255,))
    cx, cy = C[0] * SS, C[1] * SS
    for r, color in ((DOT_R + RING, ORANGE), (DOT_R, CREAM)):
        d.ellipse((cx - r * SS, cy - r * SS, cx + r * SS, cy + r * SS), fill=color + (255,))
    canvas.resize((SIZE, SIZE), Image.LANCZOS).save(out)


def render_svg(out):
    hexc = lambda c: "#%02X%02X%02X" % c
    poly = lambda c, pts: f'<polygon fill="{hexc(c)}" points="{" ".join(f"{x:.1f},{y:.1f}" for x, y in pts)}"/>'
    x0, y0, x1, y1 = BODY
    body = (f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{hexc(GROUND_TOP)}"/><stop offset="1" stop-color="{hexc(GROUND_BOTTOM)}"/>'
            f'</linearGradient></defs>'
            f'<rect x="{x0}" y="{y0}" width="{x1 - x0}" height="{y1 - y0}" rx="{RADIUS}" fill="url(#g)"/>')
    shapes = "".join(poly(c, p) for c, p in SHAPES)
    dot = (f'<circle cx="{C[0]:g}" cy="{C[1]:g}" r="{DOT_R + RING}" fill="{hexc(ORANGE)}"/>'
           f'<circle cx="{C[0]:g}" cy="{C[1]:g}" r="{DOT_R}" fill="{hexc(CREAM)}"/>')
    with open(out, "w") as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">{body}{shapes}{dot}</svg>\n')


if __name__ == "__main__":
    render_png(sys.argv[1])
    if len(sys.argv) > 2:
        render_svg(sys.argv[2])
    print("ok", *sys.argv[1:])
