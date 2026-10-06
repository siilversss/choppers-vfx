"""Texture set 3: element-specific, hand-drawn-style textures (flipbooks, decals, sprites).
Greyscale shading lives in RGB, the silhouette in alpha, so Roblox can tint them."""
import numpy as np, math, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "textures")
R = np.random.default_rng(31)


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    dx, dy = (x - n / 2 + 0.5) / (n / 2), (y - n / 2 + 0.5) / (n / 2)
    return dx, dy, np.sqrt(dx * dx + dy * dy), np.arctan2(dy, dx)


def noise(n, octaves=5, seed=0, base=4):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n), np.float32); amp = 1.0; tot = 0.0
    for o in range(octaves):
        s = base * 2 ** o
        g = r.random((s, s)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        acc += np.asarray(img, np.float32) / 255 * amp; tot += amp; amp *= 0.5
    return acc / tot


def save(name, alpha, shade=None):
    a = np.clip(alpha, 0, 1)
    img = np.zeros(a.shape + (4,), np.uint8)
    if shade is None:
        img[..., :3] = 255
    else:
        img[..., :3] = (np.clip(shade, 0, 1)[..., None] * 255).astype(np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img).save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def flipbook(name, frame_fn, n=256):
    """frame_fn(t, f) -> (alpha, shade) for a n x n frame; 16 frames in a 4x4 grid."""
    A = np.zeros((n * 4, n * 4), np.float32); S = np.ones((n * 4, n * 4), np.float32)
    for f in range(16):
        t = f / 15
        a, s = frame_fn(t, f)
        gx, gy = f % 4, f // 4
        A[gy * n:(gy + 1) * n, gx * n:(gx + 1) * n] = a
        S[gy * n:(gy + 1) * n, gx * n:(gx + 1) * n] = s
    save(name, A, S)


n = 256
dx, dy, r, a = grid(n)
NZ = [noise(n, 5, 100 + i) for i in range(6)]

# ---------------------------------------------------------------- flame tongue (rises, flickers, licks upward)
def flame(t, f):
    sh = int(t * 70)
    nz = np.roll(NZ[0], sh, 0) * 0.6 + np.roll(NZ[1], sh * 2, 0) * 0.4
    y = -dy  # up is +
    h = (y + 0.85) / 1.75                       # 0 at the base, 1 at the tip
    width = 0.62 * np.clip(1 - h, 0, 1) ** 0.85 * np.clip(h * 12, 0, 1) ** 0.4 * (1 - t * 0.3)
    wobble = (nz - 0.5) * (0.25 + 0.7 * np.clip(h, 0, 1))
    body = np.clip(1 - np.abs(dx + wobble * 0.5) / np.maximum(width, 1e-3), 0, 1) ** 0.7
    body *= np.clip((nz + 0.35 - h * 0.55 - t * 0.4) * 2.4, 0, 1)
    shade = np.clip(0.5 + (1 - np.abs(dx) / 0.6) * 0.4 + (0.35 - h) * 0.35, 0.3, 1)
    return np.clip(body * 1.5, 0, 1) * (1 - t ** 3), shade
flipbook("flame_flipbook4x4", flame)

# ---------------------------------------------------------------- rolling smoke (soft, grows, thins out)
def smoke(t, f):
    sh = int(t * 30)
    nz = np.roll(NZ[2], (sh, sh), (0, 1)) * 0.55 + np.roll(NZ[3], (-sh, sh * 2), (0, 1)) * 0.45
    rad = 0.45 + 0.5 * t ** 0.6
    w = r * (1 + (nz - 0.5) * 0.9)
    body = np.clip(1 - (w / rad) ** 2, 0, 1) ** 0.8
    alpha = np.clip(body * 1.3, 0, 1) * np.clip((nz + 0.25 - t * 0.55) * 2.2, 0, 1) * (1 - t ** 2)
    shade = np.clip(0.45 + (nz - 0.5) * 1.6 - dy * 0.25, 0.2, 1)
    return alpha, shade
flipbook("smoke_flipbook4x4", smoke)

# ---------------------------------------------------------------- dust burst (ground puff kicked outward, lumpy)
def dust(t, f):
    nz = NZ[4] * 0.6 + NZ[5] * 0.4
    rad = 0.3 + 0.65 * t ** 0.45
    w = r * (1 + (nz - 0.5) * (1.1 + t))
    body = np.clip(1 - (w / rad) ** 3, 0, 1)
    hollow = np.clip(w / rad * 1.4 - t * 0.9, 0, 1) if t > 0.2 else 1
    alpha = body * hollow * np.clip((nz + 0.55 - t * 0.85) * 1.8, 0, 1)
    shade = np.clip(0.55 + (nz - 0.5) * 1.4 - dy * 0.3, 0.25, 1)
    return alpha, shade
flipbook("dust_flipbook4x4", dust)

# ---------------------------------------------------------------- electric crackle (new branching arcs every frame)
def electric(t, f):
    img = Image.new("L", (n, n), 0); d = ImageDraw.Draw(img)
    rr = np.random.default_rng(500 + f)
    def bolt(x, y, ang, ln, w, depth):
        for _ in range(int(ln / 7)):
            ang += rr.normal(0, 0.55)
            nx, ny = x + math.cos(ang) * 7, y + math.sin(ang) * 7
            d.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
            if depth > 0 and rr.random() < 0.12:
                bolt(nx, ny, ang + rr.choice([-1, 1]) * rr.uniform(0.5, 1.1), ln * 0.45, w * 0.6, depth - 1)
            x, y = nx, ny
    for k in range(3):
        ang = rr.uniform(0, 2 * math.pi)
        bolt(n / 2 + rr.normal(0, 8), n / 2 + rr.normal(0, 8), ang, rr.uniform(70, 120), 3, 2)
    core = np.asarray(img, np.float32) / 255
    glow = np.asarray(img.filter(ImageFilter.GaussianBlur(5)), np.float32) / 255
    fade = 1 - t ** 1.5
    return np.clip(core + glow * 1.6, 0, 1) * fade * (r < 1), np.clip(0.75 + core * 0.25, 0, 1)
flipbook("electric_flipbook4x4", electric)

# ---------------------------------------------------------------- water splash (crown of droplets + sheet)
def splash(t, f):
    rr = np.random.default_rng(900)
    alpha = np.zeros((n, n), np.float32)
    y = -dy
    base = 0.75
    # a V-shaped crown of water thrown up from the impact point, then falling back
    hgt = 1.3 * math.sin(min(t * 1.6, 1.0) * math.pi * 0.5) * (1 - t * 0.6)
    for side in (-1, 0, 1):
        lean = side * (0.35 + 0.5 * t)
        cx = dx - lean * (y + base)
        sheet_w = 0.07 + 0.08 * (y + base)
        col = np.exp(-(cx / sheet_w) ** 2) * ((y + base) > 0) * ((y + base) < hgt) * (0.55 if side else 0.8)
        alpha += col * (0.6 + 0.5 * NZ[side + 1])
    for k in range(30):
        ang = rr.uniform(-math.pi * 0.9, -math.pi * 0.1)
        sp = rr.uniform(0.6, 1.2)
        px = math.cos(ang) * sp * t * 0.9
        py = -base + 0.05 + (-math.sin(ang)) * sp * t * 1.3 - 1.6 * t * t
        size = rr.uniform(0.025, 0.05) * (1 - t * 0.4)
        alpha += np.exp(-(((dx - px) ** 2 + ((y) - py) ** 2) / size ** 2))
    shade = np.clip(0.75 + NZ[1] * 0.25 + y * 0.1, 0.4, 1)
    return np.clip(alpha, 0, 1) * (1 - t ** 2.5), shade
flipbook("splash_flipbook4x4", splash)

# ---------------------------------------------------------------- decals (512)
N = 512
dx, dy, r, a = grid(N)

# frost: six-fold branching ice crystal spreading out, frosty fill
img = Image.new("L", (N, N), 0); d = ImageDraw.Draw(img)
def fern(x, y, ang, ln, w, depth):
    steps = int(ln / 5)
    for s_ in range(steps):
        nx, ny = x + math.cos(ang) * 5, y + math.sin(ang) * 5
        d.line([(x, y), (nx, ny)], fill=255, width=max(1, int(w)))
        if depth > 0 and s_ % 4 == 2:
            for sgn in (-1, 1):
                fern(nx, ny, ang + sgn * math.radians(60), ln * 0.32 * (1 - s_ / steps), w * 0.6, depth - 1)
        x, y = nx, ny; w *= 0.97
for k in range(6):
    fern(N / 2, N / 2, k * math.pi / 3 + 0.1, 230, 5, 2)
lines = np.asarray(img.filter(ImageFilter.GaussianBlur(1)), np.float32) / 255
soft = np.asarray(img.filter(ImageFilter.GaussianBlur(7)), np.float32) / 255
frost_fill = np.clip(noise(N, 5, 7) * 1.4 - 0.5, 0, 1) * np.clip(1 - r, 0, 1) * 0.5
save("frost_decal", np.clip(lines * 1.2 + soft * 0.7 + frost_fill, 0, 1) * np.clip(1.1 - r, 0, 1))

# scorch: dark burn with noisy edge, darker centre, glowing rim cracks
nz = noise(N, 6, 11)
edge = r * (1 + (nz - 0.5) * 0.7)
burn = np.clip(1 - edge / 0.8, 0, 1) ** 0.6
save("scorch_decal", burn * 0.92, shade=np.clip(0.05 + nz * 0.12 + (edge > 0.55) * 0.08, 0, 1))

# splat: liquid splatter (main blob, satellite drops, streaks)
nz = noise(N, 5, 21)
blob = np.clip(1 - (r * (1 + (nz - 0.5) * 0.9)) / 0.45, 0, 1)
alpha = np.clip(blob * 3, 0, 1)
for k in range(30):
    ang = R.uniform(0, 2 * math.pi); dist = R.uniform(0.45, 0.92); s = R.uniform(0.015, 0.06)
    px, py = math.cos(ang) * dist, math.sin(ang) * dist
    alpha += np.clip(1 - np.sqrt((dx - px) ** 2 + (dy - py) ** 2) / s, 0, 1) * 3
for k in range(10):
    ang = R.uniform(0, 2 * math.pi)
    da = np.angle(np.exp(1j * (a - ang)))
    alpha += np.clip(1 - np.abs(da) / (0.02 + 0.05 * (1 - r)), 0, 1) * (r < R.uniform(0.6, 0.85)) * 2
save("splat_decal", np.clip(alpha, 0, 1), shade=np.clip(0.55 + nz * 0.45 - r * 0.2, 0, 1))

# rune ring: two rings with procedural glyphs between them
img = Image.new("L", (N, N), 0); d = ImageDraw.Draw(img)
c = N / 2
for rad, w in ((0.93, 9), (0.73, 6), (0.66, 3)):
    d.ellipse([c - rad * c, c - rad * c, c + rad * c, c + rad * c], outline=255, width=w)
glyphs = 16
for g in range(glyphs):
    ang = g / glyphs * 2 * math.pi
    gx, gy = c + math.cos(ang) * 0.84 * c, c + math.sin(ang) * 0.84 * c
    rot = ang + math.pi / 2
    def P(u, v):  # glyph space (u along ring, v radial) -> image
        return (gx + u * math.cos(rot) - v * math.sin(rot), gy + u * math.sin(rot) + v * math.cos(rot))
    rr = np.random.default_rng(g * 7 + 3)
    strokes = rr.integers(2, 4)
    for s_ in range(strokes):
        u0, v0, u1, v1 = rr.uniform(-9, 9, 4)
        d.line([P(u0 * 1.5, v0 * 1.4), P(u1 * 1.5, v1 * 1.4)], fill=255, width=6)
    if rr.random() < 0.5:
        d.ellipse([P(-4, -4)[0] - 6, P(-4, -4)[1] - 6, P(-4, -4)[0] + 6, P(-4, -4)[1] + 6], outline=255, width=5)
ring = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2)), np.float32) / 255
glow = np.asarray(img.filter(ImageFilter.GaussianBlur(10)), np.float32) / 255
save("rune_ring", np.clip(ring * 1.3 + glow * 0.6, 0, 1))

# ripple: thin water ring with a soft inner sheen
save("ripple_ring", np.exp(-((r - 0.9) / 0.018) ** 2) + 0.35 * np.exp(-((r - 0.84) / 0.05) ** 2) + 0.15 * np.exp(-((r - 0.72) / 0.12) ** 2))

# ---------------------------------------------------------------- sprites (256)
n = 256
dx, dy, r, a = grid(n)

# leaf: pointed oval with midrib and veins, shaded
u, v = dx / 0.42, dy / 0.85
leaf = (u ** 2 + v ** 2 < 1) & (np.abs(u) < (1 - np.abs(v)) ** 0.6 * 1.05)
vein = np.exp(-(dx / 0.012) ** 2) * (np.abs(dy) < 0.8)
for k in range(-3, 4):
    vein += np.exp(-((dy - k * 0.2 + np.abs(dx) * 0.9) / 0.012) ** 2) * (np.abs(dx) < 0.36)
shade = np.clip(0.6 + dx * 0.35 + NZ[0] * 0.2 - np.clip(vein, 0, 1) * 0.25, 0.25, 1)
save("leaf", leaf.astype(np.float32) * (np.abs(dy) < 0.86), shade=shade)

# shard: elongated faceted crystal
body = (np.abs(dx) / 0.22 + np.abs(dy) / 0.92) < 1
facet = np.where(dx > 0, 0.95, 0.6) * np.where(dy < 0, 1.0, 0.85)
edge = np.exp(-(((np.abs(dx) / 0.22 + np.abs(dy) / 0.92) - 1) / 0.04) ** 2)
save("shard", np.clip(body * 0.9 + edge * 0.6, 0, 1), shade=np.clip(facet + edge * 0.3, 0, 1))

# spark streak: long thin bright streak (use with VelocityParallel)
streak = np.exp(-(dx / 0.05) ** 2) * np.clip(1 - np.abs(dy) / 0.95, 0, 1) ** 1.2 + np.exp(-((dx / 0.1) ** 2 + (dy / 0.25) ** 2)) * 0.6
save("spark_streak", np.clip(streak * 1.3, 0, 1))

# bubble: thin rim + highlight
rim = np.exp(-((r - 0.82) / 0.05) ** 2) * 0.9 + np.clip(1 - r / 0.82, 0, 1) * 0.12
hl = np.exp(-(((dx + 0.32) ** 2 + (dy + 0.35) ** 2) / 0.012))
save("bubble", np.clip(rim + hl, 0, 1) * (r < 1))

# light rays: soft fan of god-rays for holy/solar flashes
rays = np.zeros_like(r)
for k in range(18):
    ang = R.uniform(-math.pi, math.pi); w = R.uniform(0.04, 0.14); ln = R.uniform(0.5, 1.0)
    da = np.angle(np.exp(1j * (a - ang)))
    rays += np.exp(-(da / w) ** 2) * np.clip(1 - r / ln, 0, 1) ** 1.5 * R.uniform(0.4, 1.0)
save("light_rays", np.clip(rays + np.exp(-(r / 0.18) ** 2), 0, 1))

# ember: soft hot dot (tiny core, wide falloff)
save("ember", np.clip(np.exp(-(r / 0.12) ** 2) + 0.45 * np.exp(-(r / 0.45) ** 2), 0, 1))

# ---------------------------------------------------------------- bold bolt strips for Beams (along X), 4 variants stacked? no: one per file
def bolt_strip(name, seed, jag=13, core=4.0):
    W, H = 512, 128
    rr = np.random.default_rng(seed)
    img = Image.new("L", (W, H), 0); d = ImageDraw.Draw(img)
    n = 18
    ys = np.cumsum(rr.normal(0, jag, n + 1)); ys -= np.linspace(ys[0], ys[-1], n + 1)
    ys = np.clip(ys, -H * 0.36, H * 0.36) + H / 2
    xs = np.linspace(0, W, n + 1)
    pts = list(zip(xs, ys))
    d.line(pts, fill=255, width=int(core), joint="curve")
    for k in range(5):  # forks
        i = rr.integers(2, n - 2)
        x0, y0 = pts[i]
        ang = rr.uniform(-1.0, 1.0)
        L = rr.uniform(30, 70)
        fork = [(x0, y0)]
        for s in range(4):
            x0 += L / 4; y0 += math.sin(ang) * L / 4 + rr.normal(0, 4)
            fork.append((x0, y0))
        d.line(fork, fill=200, width=max(1, int(core * 0.5)))
    c = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    g = np.asarray(img.filter(ImageFilter.GaussianBlur(7)), np.float32) / 255
    save(name, np.clip(c * 1.2 + g * 1.4, 0, 1), shade=np.clip(0.7 + c * 0.3, 0, 1))
bolt_strip("bolt_bold", 41)

# ---------------------------------------------------------------- light column for Beams: solid core with soft edges (across Y)
W, H = 256, 128
y = (np.arange(H)[:, None] - H / 2) / (H / 2)
col = np.clip(1 - np.abs(y) / 0.55, 0, 1) ** 0.6 + 0.5 * np.exp(-(y / 0.85) ** 2)
streak = 0.85 + 0.15 * noise(256, 3, 77)[:H, :W]
save("light_column", np.clip(col * streak, 0, 1) * np.ones((1, W)))
