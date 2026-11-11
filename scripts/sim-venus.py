# sim-venus.py - Globo de Venus 2D girando, nativo 1080x1920
# Salida: 03-visual/clips/venus-2d.mp4 (12 s, 30 fps, sin audio)
#
# Textura procedural (bandas + nubes) mapeada a una esfera con proyeccion ortografica.
# No usa imagenes externas: todo se genera con numpy/PIL.
import os, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1080, 1920
FPS = 30
DUR = 12.0
N = int(DUR * FPS)
OUT = "logs/_sim-venus"
SALIDA = sys.argv[1] if len(sys.argv) > 1 else "03-visual/clips/venus-2d.mp4"

os.makedirs("03-visual/clips", exist_ok=True)
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)

rng = np.random.default_rng(11)
CX, CY, R = 540, 760, 380

# ---------- textura ----------
TW, TH = 1024, 512
lat = np.linspace(-np.pi / 2, np.pi / 2, TH)[:, None]
lon = np.linspace(0, 2 * np.pi, TW, endpoint=False)[None, :]
base = 0.5 + 0.5 * np.sin(lat * 7 + 1.1 * np.sin(lon * 3))
clouds = np.zeros((TH, TW))
for f in (2, 3, 5, 9, 14):
    clouds += np.sin(lon * f + rng.uniform(0, 2 * np.pi) + lat * 3) / f
n = base * 0.55 + clouds * 0.45
n = (n - n.min()) / (n.max() - n.min())
r = 0.78 + 0.20 * n
g = 0.44 + 0.26 * n
b = 0.18 + 0.12 * n
pole = np.cos(lat) ** 0.45
r *= pole; g *= pole; b *= pole
tex = np.clip(np.stack([r, g, b], axis=-1), 0, 1)
# suavizar un poco las nubes
timg = Image.fromarray((tex * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
tex = np.asarray(timg).astype(np.float32) / 255.0

# ---------- fondo ----------
yy, xx = np.mgrid[0:H, 0:W]
d = np.sqrt(((xx - CX) / W) ** 2 + ((yy - CY) / H) ** 2)
glow = np.clip(1 - d * 2.0, 0, 1) ** 2
bg = np.zeros((H, W, 3), dtype=np.float32)
bg[..., 0] = 0.03 + 0.10 * glow
bg[..., 1] = 0.02 + 0.04 * glow
bg[..., 2] = 0.07 + 0.18 * glow
# estrellas
ns = 700
sx = rng.integers(0, W, ns); sy = rng.integers(0, H, ns)
bg[sy, sx] = 0.9
# halo atmosferico estatico
rr = np.sqrt((xx - CX) ** 2 + (yy - CY) ** 2)
halo = np.clip(1 - np.abs(rr - R) / 55.0, 0, 1) ** 2
bg[..., 0] += 0.35 * halo
bg[..., 1] += 0.18 * halo
bg[..., 2] += 0.05 * halo
bg = np.clip(bg, 0, 1)

# ---------- grilla del disco ----------
x0, x1 = CX - R, CX + R
y0, y1 = CY - R, CY + R
gy, gx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
nx = (gx - CX) / R
ny = (gy - CY) / R
r2 = nx * nx + ny * ny
mask = r2 <= 1.0
nz = np.sqrt(np.clip(1 - r2, 0, 1))
light = np.clip(nx * 0.55 + ny * (-0.45) + nz * 0.70, 0, 1)
shade = 0.16 + 0.95 * light

for k in range(N):
    t = k / FPS
    ang = 2 * np.pi * 1.15 * (t / DUR)
    lon_map = (np.arctan2(nx, nz) + ang)
    lat_map = np.arcsin(np.clip(ny, -1, 1))
    u = ((lon_map / (2 * np.pi)) % 1.0 * (TW - 1)).astype(np.int32)
    v = ((0.5 - lat_map / np.pi) * (TH - 1)).astype(np.int32)
    col = tex[v, u] * shade[..., None]
    img = bg.copy()
    sub = img[y0:y1 + 1, x0:x1 + 1]
    sub[mask] = np.clip(col[mask], 0, 1)

    im = Image.fromarray((img * 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    # marcador de rotacion (punto fijo en el ecuador de la textura)
    lx, lz = np.sin(ang), np.cos(ang)
    if lz > 0.02:
        mx = CX + R * lx
        my = CY
        d.ellipse([mx - 9, my - 9, mx + 9, my + 9], fill=(255, 255, 255))
        d.ellipse([mx - 16, my - 16, mx + 16, my + 16], outline=(255, 240, 210), width=2)
    im.save(os.path.join(OUT, "f%04d.png" % k))
    if k % 30 == 0:
        print("frame %d/%d" % (k, N))

cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
       "-framerate", str(FPS), "-i", os.path.join(OUT, "f%04d.png"),
       "-c:v", "libx264", "-preset", "medium", "-crf", "18",
       "-pix_fmt", "yuv420p", "-r", str(FPS), SALIDA]
subprocess.run(cmd, check=True)
dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", SALIDA],
                     capture_output=True, text=True).stdout.strip()
print("OK %s | %.1fs" % (SALIDA, float(dur or 0)))
