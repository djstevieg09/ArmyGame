"""Generates assets/fx/blood.png: an irregular splat with droplets (RGBA)."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter
random.seed(3)
S = 256
a = Image.new("L", (S, S), 0)
d = ImageDraw.Draw(a)
for i in range(14):
    r = random.uniform(18, 46)
    x = S / 2 + random.gauss(0, 18); y = S / 2 + random.gauss(0, 18)
    d.ellipse([x - r, y - r, x + r, y + r], fill=255)
for i in range(60):
    ang = random.random() * math.tau
    dist = random.uniform(55, 118)
    r = random.uniform(2, 9) * (1.2 - dist / 140)
    x = S / 2 + math.cos(ang) * dist; y = S / 2 + math.sin(ang) * dist
    d.ellipse([x - r, y - r, x + r, y + r], fill=255)
a = a.filter(ImageFilter.GaussianBlur(2.2)).point(lambda v: 255 if v > 110 else int(v * 1.6))
col = Image.new("RGBA", (S, S))
px = col.load(); ap = a.load()
for y in range(S):
    for x in range(S):
        v = ap[x, y]
        dd = math.hypot(x - S / 2, y - S / 2) / (S / 2)
        k = 0.75 + 0.25 * random.random()
        px[x, y] = (int((95 + 40 * dd) * k), int(8 * k), int(10 * k), int(v * 0.92))
col.save(sys.argv[1])
