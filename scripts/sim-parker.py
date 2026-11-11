# sim-parker.py - Animacion 2D de la Parker Solar Probe: orbita + velocimetro
# Salida: 03-visual/clips/parker-2d.mp4 (12 s, 30 fps, 1080x1920, sin audio)
import os, shutil, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1080, 1920
FPS = 30
DUR = 12.0
N = int(DUR * FPS)
OUT = "logs/_sim-parker"
SALIDA = sys.argv[1] if len(sys.argv) > 1 else "03-visual/clips/parker-2d.mp4"

os.makedirs("03-visual/clips", exist_ok=True)
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)

rng = np.random.default_rng(5)
CX, CY = 540, 900          # centro de la orbita
A, B = 620, 560            # semiejes
SUN = (540, 634)           # foco (Sol)
SUN_R = 70

# ---------- fondo ----------
yy, xx = np.mgrid[0:H, 0:W]
d = np.sqrt(((xx - SUN[0]) / W) ** 2 + ((yy - SUN[1]) / H) ** 2)
glow = np.clip(1 - d * 2.4, 0, 1) ** 2
bg = np.zeros((H, W, 3), dtype=np.uint8)
bg[..., 0] = (6 + 55 * glow).astype(np.uint8)
bg[..., 1] = (4 + 22 * glow).astype(np.uint8)
bg[..., 2] = (18 + 38 * glow).astype(np.uint8)
for _ in range(700):
    x = rng.integers(0, W); y = rng.integers(0, H)
    v = rng.integers(120, 256)
    bg[y, x] = (v, v, v)
base = Image.fromarray(bg, "RGB").convert("RGBA")

# ---------- glow del Sol ----------
G = 500
gy, gx = np.mgrid[-G // 2:G // 2, -G // 2:G // 2]
gr = np.sqrt(gx * gx + gy * gy)
alpha = np.clip(1 - gr / (G / 2), 0, 1) ** 2
sun_glow = np.zeros((G, G, 4), dtype=np.uint8)
sun_glow[..., 0] = 255
sun_glow[..., 1] = 190
sun_glow[..., 2] = 80
sun_glow[..., 3] = (alpha * 210).astype(np.uint8)
sun_img = Image.fromarray(sun_glow, "RGBA")

# ---------- fuentes ----------
F_TIT = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", 52)
F_LAB = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 34)
F_NUM = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", 150)
F_UNI = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", 46)

def centrar(draw, texto, font, y, color):
    b = draw.textbbox((0, 0), texto, font=font)
    draw.text(((W - (b[2] - b[0])) / 2 - b[0], y), texto, font=font, fill=color)

orbit_box = [CX - A, CY - B, CX + A, CY + B]
trail = []

for k in range(N):
    t = k / FPS
    ang = np.pi / 2 + 2 * np.pi * (t / DUR)
    px = CX + A * np.cos(ang)
    py = CY + B * np.sin(ang)
    v = 692000 * (0.18 + 0.82 * (0.5 - 0.5 * np.cos(2 * np.pi * t / DUR)) ** 2)

    img = base.copy()
    d = ImageDraw.Draw(img)
    # orbita
    d.ellipse(orbit_box, outline=(70, 95, 140, 190), width=3)

    # Sol
    img.alpha_composite(sun_img, (SUN[0] - G // 2, SUN[1] - G // 2))
    d = ImageDraw.Draw(img)
    d.ellipse([SUN[0] - SUN_R, SUN[1] - SUN_R, SUN[0] + SUN_R, SUN[1] + SUN_R], fill=(255, 250, 225, 255))
    d.ellipse([SUN[0] - SUN_R + 14, SUN[1] - SUN_R + 14, SUN[0] + SUN_R - 14, SUN[1] + SUN_R - 14], fill=(255, 196, 90, 255))

    # estela
    trail.append((px, py))
    if len(trail) > 28:
        trail.pop(0)
    for i, (tx, ty) in enumerate(trail):
        f = i / len(trail)
        c = (int(255 * f), int(150 * f), int(40 * f), 255)
        r = 2 + 3 * f
        d.ellipse([tx - r, ty - r, tx + r, ty + r], fill=c)

    # sonda: escudo mirando al Sol + cuerpo
    ax, ay = SUN[0] - px, SUN[1] - py
    n = max(1.0, (ax * ax + ay * ay) ** 0.5)
    ux, uy = ax / n, ay / n
    sx, sy = px + ux * 10, py + uy * 10
    d.ellipse([sx - 13, sy - 13, sx + 13, sy + 13], fill=(240, 240, 245, 255), outline=(255, 170, 60, 255), width=3)
    d.ellipse([px - 7, py - 7, px + 7, py + 7], fill=(255, 190, 70, 255))
    d.ellipse([px - 2, py - 2, px + 2, py + 2], fill=(80, 220, 255, 255))

    # textos
    d = ImageDraw.Draw(img)
    centrar(d, "PARKER SOLAR PROBE", F_TIT, 80, (255, 255, 255, 235))
    centrar(d, "VELOCIDAD", F_LAB, 1560, (150, 200, 235, 220))
    num = ("{:,}".format(int(v))).replace(",", ".")
    centrar(d, num, F_NUM, 1620, (255, 255, 255, 255))
    centrar(d, "km/h", F_UNI, 1780, (0, 200, 255, 255))

    img.convert("RGB").save(os.path.join(OUT, "f%04d.png" % k))
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
