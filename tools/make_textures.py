"""Procedural VFX textures for Chop Trees For Anime.
All textures are white (or greyscale) with alpha, so Roblox can tint them per weapon (Color3 / ColorSequence)."""
import numpy as np
from PIL import Image, ImageFilter
import os, math
OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
rng = np.random.default_rng(7)

def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = (x - n / 2 + 0.5) / (n / 2), (y - n / 2 + 0.5) / (n / 2)
    return dx, dy, np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)

def fbm(n, octaves=5, seed=0):
    """smooth value-noise fractal in 0..1, tileable"""
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n), np.float32); amp = 1.0; tot = 0
    for o in range(octaves):
        s = 4 * 2 ** o
        g = r.random((s, s)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        # make it tile by wrapping a blurred copy
        acc += np.asarray(img, np.float32) / 255 * amp; tot += amp; amp *= 0.5
    return acc / tot

def save(name, alpha, rgb=None):
    a = np.clip(alpha, 0, 1)
    n = a.shape[0]
    img = np.zeros((a.shape[0], a.shape[1], 4), np.uint8)
    if rgb is None:
        img[..., :3] = 255
    else:
        img[..., :3] = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, name + ".png"))
    print("wrote", name)

N = 512

# 1) crescent slash: a sharp bright edge with a soft trailing body (for the big swing arc)
dx, dy, r, a = grid(N)
span = np.clip((a + np.pi * 0.95) / (np.pi * 1.3), 0, 1)          # 0..1 along the arc
inside = ((a + np.pi * 0.95) / (np.pi * 1.3) > 0) & ((a + np.pi * 0.95) / (np.pi * 1.3) < 1)
thick = np.sin(np.clip(span, 0, 1) * np.pi) ** 0.7 * 0.36 + 0.004
edge_r = 0.86
d_out = r - edge_r                                                 # >0 outside the edge
body = np.where(d_out < 0, np.clip(1 + d_out / thick, 0, 1) ** 1.5, 0)   # soft body inside the edge
edge = np.exp(-(d_out / 0.012) ** 2)                               # razor edge line
streaks = 0.8 + 0.2 * np.sin(r * 38 + fbm(N, 3, 1) * 9)  # soft motion streaks along the arc
alpha = np.where(inside, (body * 1.0 * streaks + edge * 1.2) * np.clip(span * 2.5, 0, 1) * np.clip((1 - span) * 6, 0, 1), 0)
save("slash_crescent", alpha)

# 2) shockwave ring: crisp outer rim, soft inner falloff (ground / air rings)
dx, dy, r, a = grid(N)
rim = np.exp(-((r - 0.9) / 0.025) ** 2)
inner = np.clip((r - 0.45) / 0.45, 0, 1) ** 3 * (r < 0.9)
noise = fbm(N, 4, 2)
save("shock_ring", (rim + inner * 0.55) * (0.75 + 0.25 * noise))

# 3) soft glow orb
dx, dy, r, a = grid(256)
save("glow_soft", np.exp(-(r / 0.42) ** 2) * (r < 1))

# 4) 4-point spark / twinkle
dx, dy, r, a = grid(256)
star = np.exp(-np.abs(dx) / 0.025) * np.exp(-np.abs(dy) / 0.55) + np.exp(-np.abs(dy) / 0.025) * np.exp(-np.abs(dx) / 0.55)
star += 0.5 * (np.exp(-np.abs(dx + dy) / 0.03) + np.exp(-np.abs(dx - dy) / 0.03)) * np.exp(-r / 0.3)
save("spark_star", np.clip(star + np.exp(-(r / 0.12) ** 2), 0, 1) * (r < 1))

# 5) wispy smoke puff (greyscale body so it can be lit)
dx, dy, r, a = grid(256)
n1 = fbm(256, 5, 3)
mask = np.clip(1 - r / 0.95, 0, 1) ** 1.4
smoke = np.clip((n1 - 0.2) * 2.0 + mask * 0.6, 0, 1) * mask
save("smoke_wisp", smoke * 0.95, rgb=np.dstack([0.75 + 0.25 * n1] * 3))

# 6) lightning bolt strip for Beams (horizontal, tiles along X)
W, H = 512, 128
img = np.zeros((H, W), np.float32)
yy = np.arange(H)[:, None].astype(np.float32)
def bolt(img, amp, width, glow, seed):
    r2 = np.random.default_rng(seed)
    pts = np.cumsum(r2.normal(0, amp, 33)); pts -= np.linspace(pts[0], pts[-1], 33)  # ends meet -> tiles
    xs = np.linspace(0, W, 33)
    cy = H / 2 + np.interp(np.arange(W), xs, pts)
    d = np.abs(yy - cy[None, :])
    return np.exp(-(d / width) ** 2) + glow * np.exp(-(d / (width * 7)) ** 2)
img = bolt(img, 9, 2.0, 0.35, 4) + 0.55 * bolt(img, 14, 1.2, 0.0, 9)
save("lightning_strip", np.clip(img, 0, 1))

# 7) energy trail: bright core line fading to soft edges with flowing streaks (for Trails / Beams)
W, H = 512, 128
y = (np.arange(H)[:, None] - H / 2) / (H / 2)
x = np.arange(W)[None, :] / W
streak = 0.6 + 0.4 * fbm(512, 4, 5)[:H, :]
core = np.exp(-(y / 0.12) ** 2) + 0.6 * np.exp(-(y / 0.45) ** 2) * streak
save("energy_trail", np.clip(core, 0, 1) * np.ones((1, W)))

# 8) impact burst: radial spikes for a hit flash
dx, dy, r, a = grid(N)
spikes = np.zeros_like(r)
for k in range(14):
    ang = rng.uniform(-np.pi, np.pi); ln = rng.uniform(0.55, 0.98); w = rng.uniform(0.02, 0.05)
    da = np.angle(np.exp(1j * (a - ang)))
    spikes = np.maximum(spikes, np.exp(-(da / (w / np.maximum(r, 0.05))) ** 2) * np.clip(1 - r / ln, 0, 1))
save("impact_burst", np.clip(spikes + np.exp(-(r / 0.22) ** 2), 0, 1))

# 9) ground cracks decal
dx, dy, r, a = grid(N)
crack = np.zeros((N, N), np.float32)
im = Image.new("L", (N, N), 0)
from PIL import ImageDraw
dr = ImageDraw.Draw(im)
def branch(x, y, ang, ln, w, depth):
    if depth == 0 or ln < 8: return
    for _ in range(int(ln / 6)):
        ang += rng.normal(0, 0.25)
        nx, ny = x + math.cos(ang) * 6, y + math.sin(ang) * 6
        dr.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
        x, y = nx, ny; w *= 0.985
    branch(x, y, ang + rng.uniform(0.3, 0.8), ln * 0.55, w * 0.7, depth - 1)
    branch(x, y, ang - rng.uniform(0.3, 0.8), ln * 0.5, w * 0.7, depth - 1)
for k in range(9):
    ang = k / 9 * 2 * math.pi + rng.normal(0, 0.2)
    branch(N / 2, N / 2, ang, rng.uniform(120, 200), 7, 3)
c = np.asarray(im.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
glow = np.asarray(im.filter(ImageFilter.GaussianBlur(9)), np.float32) / 255
save("ground_cracks", np.clip(c * 1.4 + glow * 0.8, 0, 1) * np.clip(1.15 - r, 0, 1))

# 10) fire/energy burst flipbook, 4x4 frames of 256px (1024x1024), for ParticleEmitter FlipbookLayout Grid4x4
F, n = 16, 256
sheet = np.zeros((n * 4, n * 4), np.float32)
shade_sheet = np.ones((n * 4, n * 4), np.float32)
dx, dy, r, a = grid(n)
base_noise = [fbm(n, 5, 20 + i) for i in range(3)]
for f in range(F):
    t = f / (F - 1)
    radius = 0.38 + 0.57 * t ** 0.5                 # grows to fill the frame
    # each frame samples the noise at a drifting offset so the billows churn instead of just scaling
    sh = int(t * 40)
    n0 = np.roll(base_noise[0], (sh, -sh), (0, 1)); n1 = np.roll(base_noise[1], (-sh * 2, sh), (0, 1))
    turb = n0 * 0.6 + n1 * 0.4
    warped = r * (1 + (turb - 0.5) * (0.9 + 0.5 * t))  # lumpy, billowing silhouette from frame 1
    body = np.clip(1 - (warped / radius) ** 2, 0, 1) ** 0.6
    # volumetric shading: bright churning lobes, darker creases
    shade = np.clip(0.45 + (turb - 0.5) * 2.2 + (1 - r / max(radius, 0.01)) * 0.35, 0.15, 1)
    hollow = np.clip((warped / radius) * 1.3 - (t - 0.3) * 1.4, 0, 1) if t > 0.3 else 1.0  # burns out from the middle
    v = np.clip(body * 1.6, 0, 1) * (1.15 - t * 0.8) * hollow
    v *= np.clip((base_noise[2] + 0.6 - t * 0.8) * 1.7, 0, 1)   # breaks up into wisps at the end
    gx, gy = f % 4, f // 4
    sheet[gy * n:(gy + 1) * n, gx * n:(gx + 1) * n] = np.clip(v, 0, 1) * (r < 1)
    shade_sheet[gy * n:(gy + 1) * n, gx * n:(gx + 1) * n] = shade * (1 - 0.35 * t)
save("burst_flipbook4x4", sheet, rgb=np.dstack([shade_sheet] * 3))
