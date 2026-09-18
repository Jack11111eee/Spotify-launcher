#!/usr/bin/env python3
"""生成启动器图标（icon/SpotifyProxy.icns）。

底图直接取自本机 Spotify.app 的真实图标，所以网格、品牌色、三条弧线的形状
天然和 Spotify 完全一致 —— 我们只加一枚右下角的徽标。

网格参数是量出来的，不是查来的：把 Spotify 图标的 alpha 通道和超椭圆做拟合，
n=5.0 时 IoU 0.9952，图形主体 824/1024、四周留白 100px。

徽标尺寸按档位单独调：大尺寸画得出绕行箭头，小尺寸留不住细节就退化成圆点，
16px 干脆不加 —— 那个尺寸下任何徽标都会糊成一个像渲染瑕疵的黑点。
"""
import glob
import math
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

SPOTIFY_ICNS = "/Applications/Spotify.app/Contents/Resources/AppIcon.icns"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "SpotifyProxy.icns")

SIZE, BODY, MARGIN = 1024, 824, 100
GREEN, DARK = (30, 215, 96), (18, 18, 18)
BADGE_CENTER = 0.80  # 圆心固定在 body 的 0.80 处，故半径上限 = 1.00 - 0.80 = 0.20

# 每一档的 (徽标半径比例, 是否画箭头)；None 表示这一档不加徽标
STAGES = {
    1024: (0.165, True),
    512: (0.165, True),
    256: (0.165, True),
    128: (0.175, True),
    64: (0.190, True),
    32: (0.200, False),  # 箭头在这个尺寸会糊成一团脏点，退化成纯圆点
    16: None,            # 这个尺寸任何徽标都像个渲染瑕疵，干脆不加
}

# iconutil 要求的文件名 -> 像素尺寸
ICONSET_FILES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def extract_spotify_icon():
    if not os.path.exists(SPOTIFY_ICNS):
        sys.exit(f"找不到 {SPOTIFY_ICNS} —— 需要装好 Spotify。")
    with tempfile.TemporaryDirectory() as td:
        iconset = os.path.join(td, "base.iconset")
        subprocess.run(["iconutil", "-c", "iconset", SPOTIFY_ICNS, "-o", iconset], check=True)
        pngs = glob.glob(os.path.join(iconset, "*.png"))
        if not pngs:
            sys.exit("从 Spotify 图标里没解出任何 PNG。")
        biggest = max(pngs, key=lambda p: Image.open(p).size[0])
        return Image.open(biggest).convert("RGBA").copy()


def draw_badge(layer, size, ss, radius, glyph):
    d = ImageDraw.Draw(layer)
    k = size / SIZE
    bx = (BODY * BADGE_CENTER + MARGIN) * k * ss
    by = bx
    br = BODY * min(radius, 1.0 - BADGE_CENTER) * k * ss
    # 深色外圈是「敲掉」的底：徽标压在绿圆上时靠它把两者分开
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=DARK)
    ir = br - max(1, int(br * 0.20))
    d.ellipse([bx - ir, by - ir, bx + ir, by + ir], fill=GREEN)
    if not glyph:
        return
    # 绕行箭头：一段圆弧 + 末端三角形箭头
    r = ir * 0.52
    w = max(1, int(ir * 0.20))
    d.arc([bx - r, by - r, bx + r, by + r], start=150, end=380, fill=DARK, width=w)
    a = math.radians(380)
    ex, ey = bx + r * math.cos(a), by + r * math.sin(a)
    tang = a + math.pi / 2
    L, W = w * 2.0, w * 1.5
    d.polygon(
        [
            (ex + L * math.cos(tang), ey + L * math.sin(tang)),
            (ex + W * math.cos(tang + math.pi / 2), ey + W * math.sin(tang + math.pi / 2)),
            (ex + W * math.cos(tang - math.pi / 2), ey + W * math.sin(tang - math.pi / 2)),
        ],
        fill=DARK,
    )


def render(base, size):
    """在目标尺寸上原生绘制徽标，而不是从 1024 缩下来，否则小尺寸会糊。"""
    im = base.resize((size, size), Image.LANCZOS)
    stage = STAGES.get(size)
    if stage is None:
        return im
    radius, glyph = stage
    ss = 8 if size <= 64 else 4
    layer = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw_badge(layer, size, ss, radius, glyph)
    return Image.alpha_composite(im, layer.resize((size, size), Image.LANCZOS))


def main():
    base = extract_spotify_icon()
    with tempfile.TemporaryDirectory() as td:
        iconset = os.path.join(td, "out.iconset")
        os.makedirs(iconset)
        for fname, px in ICONSET_FILES:
            render(base, px).save(os.path.join(iconset, fname))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT], check=True)
    print(f"已生成 {OUT} ({os.path.getsize(OUT) // 1024} KB)")
    for size in sorted(STAGES, reverse=True):
        stage = STAGES[size]
        what = "不加徽标" if stage is None else f"半径 {stage[0]:.3f}，箭头{'有' if stage[1] else '无'}"
        print(f"  {size:>5}px  {what}")


if __name__ == "__main__":
    main()