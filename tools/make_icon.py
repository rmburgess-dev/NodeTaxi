#!/usr/bin/env python3
"""Generate the original NodeTaxi project icon (no third-party artwork)."""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "docs"
S = 1024  # draw at 4x, downscale to 512/256
BG = (16, 24, 32, 255)
GRID = (31, 45, 56, 255)
BORDER = (47, 67, 80, 255)
YELLOW = (255, 210, 74, 255)
YELLOW_DIM = (255, 210, 74, 110)
GREEN = (89, 217, 142, 255)
ORANGE = (224, 154, 74, 255)
INK = (12, 18, 24, 255)


def bezier(points, t):
    # de Casteljau for a cubic
    p = list(points)
    while len(p) > 1:
        p = [
            ((1 - t) * p[i][0] + t * p[i + 1][0], (1 - t) * p[i][1] + t * p[i + 1][1])
            for i in range(len(p) - 1)
        ]
    return p[0]


def main():
    OUT.mkdir(exist_ok=True)
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    d.rounded_rectangle((16, 16, S - 16, S - 16), radius=180, fill=BG, outline=BORDER, width=10)

    # faint map grid
    for i in range(1, 8):
        x = 16 + (S - 32) * i / 8
        y = 16 + (S - 32) * i / 8
        d.line((x, 40, x, S - 40), fill=GRID, width=4)
        d.line((40, y, S - 40, y), fill=GRID, width=4)

    route = [(190, 810), (330, 640), (520, 690), (760, 300)]
    pts = [bezier(route, i / 400) for i in range(401)]

    # dashed route (accumulate the pattern across short segments)
    dash, gap = 52, 34
    segments = [dash, gap]
    seg_index = 0
    remaining = segments[seg_index]
    prev = pts[0]
    for point in pts[1:]:
        dx, dy = point[0] - prev[0], point[1] - prev[1]
        seg_len = (dx * dx + dy * dy) ** 0.5
        if seg_len <= 0:
            continue
        travelled = 0.0
        while travelled < seg_len:
            take = min(seg_len - travelled, remaining)
            if seg_index == 0:
                t0, t1 = travelled / seg_len, (travelled + take) / seg_len
                a = (prev[0] + dx * t0, prev[1] + dy * t0)
                b = (prev[0] + dx * t1, prev[1] + dy * t1)
                d.line((a, b), fill=YELLOW, width=20)
            travelled += take
            remaining -= take
            if remaining <= 1e-9:
                seg_index = (seg_index + 1) % 2
                remaining = segments[seg_index]
        prev = point

    # nodes
    for (x, y), color in (((190, 810), GREEN), ((760, 300), ORANGE)):
        d.ellipse((x - 44, y - 44, x + 44, y + 44), fill=INK)
        d.ellipse((x - 34, y - 34, x + 34, y + 34), fill=color)

    # hollow "near node" ring hint behind the first node
    d.ellipse((190 - 74, 810 - 74, 190 + 74, 810 + 74), outline=YELLOW_DIM, width=10)

    for name, size in (("icon-512.png", 512), ("icon-256.png", 256)):
        img.resize((size, size), Image.LANCZOS).save(OUT / name)
        print(OUT / name)


if __name__ == "__main__":
    main()
