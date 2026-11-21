"""Draws the Lumen app icon. Run: python3 Packaging/make_icon.py  (needs Pillow + NumPy)"""
import os
import numpy as np
from PIL import Image, ImageFilter
S = 4096                     # 4x supersampling of 1024
k = S / 1024
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
cx = cy = S / 2

def smooth_mask(d, aa=1.5 * k):
    # d: signed distance (negative inside)
    return np.clip(0.5 - d / aa, 0, 1)

# --- squircle body (Apple-style continuous corners via superellipse) ---
half = 824 * k / 2
n = 5.0
u = np.abs(xx - cx) / half
v = np.abs(yy - (cy - 6 * k)) / half
f = (u ** n + v ** n) ** (1 / n)
body = np.clip((1 - f) * half / (1.5 * k), 0, 1)

img = np.zeros((S, S, 4), np.float32)

# shadow
sh = Image.fromarray((np.clip((1 - ((np.abs(xx - cx) / half) ** n + (np.abs(yy - cy - 14 * k) / half) ** n) ** (1 / n)) * half / (1.5 * k), 0, 1) * 255).astype(np.uint8))
sh = sh.filter(ImageFilter.GaussianBlur(28 * k))
sha = np.asarray(sh).astype(np.float32) / 255 * 0.28
img[..., 3] = sha

# paper gradient
t = (yy - (cy - half)) / (2 * half)
top = np.array([0.985, 0.982, 0.975]); bot = np.array([0.905, 0.900, 0.890])
paper = top[None, None, :] * (1 - t[..., None]) + bot[None, None, :] * t[..., None]

def over(rgb, a):
    global img
    a = a[..., None]
    out_a = a + img[..., 3:4] * (1 - a)
    out_rgb = (rgb * a + img[..., :3] * img[..., 3:4] * (1 - a)) / np.maximum(out_a, 1e-6)
    img = np.concatenate([out_rgb, out_a], axis=-1)

over(paper, body)

r = np.hypot(xx - cx, yy - cy)
ang = (np.degrees(np.arctan2(xx - cx, -(yy - cy))) + 360) % 360   # 0 at 12 o'clock, clockwise

# soft shadow under the ring
R_out, R_in = 316 * k, 232 * k
ring_sd = np.maximum(r - R_out, R_in - r)
ring_soft = Image.fromarray((smooth_mask(ring_sd + 0) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(18 * k))
rs = np.asarray(ring_soft).astype(np.float32) / 255
rs = np.roll(rs, int(10 * k), axis=0)
over(np.zeros_like(paper), rs * 0.16 * body)

# --- zone-system ring: 11 tonal steps, black at top going clockwise to white ---
steps = 11
gap = 1.1  # degrees
seg = 360 / steps
idx = np.floor(ang / seg)
local = ang - idx * seg
gap_mask = np.clip((np.minimum(local, seg - local) - gap / 2) * (np.pi / 180) * r / (1.2 * k), 0, 1)
tone = idx / (steps - 1)
# perceptual-ish ramp
gray = 0.07 + 0.93 * (tone ** 0.9)
ring_rgb = np.stack([gray, gray * 0.998, gray * 0.992], axis=-1)
ring_a = smooth_mask(ring_sd) * gap_mask * body
over(ring_rgb, ring_a)
# hairline around the ring so the white steps still read on paper
for R in (R_out, R_in):
    line = np.clip(1 - np.abs(r - R) / (0.9 * k), 0, 1) * 0.10
    over(np.zeros_like(paper), line * body)

# --- central lens ---
R_lens = 172 * k
lens_a = smooth_mask(r - R_lens)
lt = np.clip((r / R_lens), 0, 1)
lens_rgb = np.stack([0.16 - 0.08 * lt, 0.16 - 0.08 * lt, 0.17 - 0.08 * lt], axis=-1)
over(lens_rgb, lens_a)
# inner ring of the lens
inner = np.clip(1 - np.abs(r - R_lens * 0.72) / (1.2 * k), 0, 1) * 0.18
over(np.ones_like(paper), inner * lens_a)
# specular highlight (soft ellipse upper-left)
hx, hy = cx - 56 * k, cy - 70 * k
e = ((xx - hx) / (86 * k)) ** 2 + ((yy - hy) / (46 * k)) ** 2
spec = np.clip(1 - e, 0, 1) ** 2.2 * 0.22 * lens_a
over(np.ones_like(paper), spec)
# small bright glint
g = np.hypot(xx - (cx + 52 * k), yy - (cy + 46 * k))
over(np.ones_like(paper), smooth_mask(g - 5 * k) * 0.18 * lens_a)

# subtle top inner highlight on the body edge
edge = np.clip(1 - np.abs(f - 0.985) / 0.006, 0, 1) * np.clip((cy - yy) / half, 0, 1) * 0.5
over(np.ones_like(paper), edge * body)

out = (np.clip(img, 0, 1) * 255).astype(np.uint8)
big = Image.fromarray(out, 'RGBA').resize((1024, 1024), Image.LANCZOS)
HERE = os.path.dirname(os.path.abspath(__file__))
big.save(os.path.join(HERE, '..', 'Sources', 'Lumen', 'Resources', 'AppIcon.png'))
# icns (Pillow writes all standard sizes)
big.save(os.path.join(HERE, 'AppIcon.icns'), sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])
print("ok")
