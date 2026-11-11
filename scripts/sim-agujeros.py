# sim-agujeros.py - Simulacion 2D estilizada de dos agujeros negros fusionandose
# Salida: frames PNG 1080x1920 -> MP4 30 fps (sin audio)
#
# Uso:
#   python scripts/sim-agujeros.py [salida.mp4]
#
# No es relatividad numerica: es una simulacion ilustrativa (inspiral + fusion + anillos).
import os, subprocess, sys, shutil
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle

W, H = 1080, 1920
FPS = 30
DUR = 12.0
N = int(DUR * FPS)
T_MERGE = 8.2
OUT = "logs/_sim-bh"
SALIDA = sys.argv[1] if len(sys.argv) > 1 else "03-visual/clips/bh-2d.mp4"

rng = np.random.default_rng(7)
os.makedirs("03-visual/clips", exist_ok=True)
if os.path.isdir(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)

# --- fondo: gradiente morado/azul ---
yy, xx = np.mgrid[0:H, 0:W]
cx, cy = W / 2, H / 2
d = np.sqrt(((xx - cx) / W) ** 2 + ((yy - cy) / H) ** 2)
glow = np.clip(1.0 - d * 2.2, 0, 1) ** 2
bg = np.zeros((H, W, 3))
bg[..., 0] = 0.07 + 0.30 * glow
bg[..., 1] = 0.03 + 0.10 * glow
bg[..., 2] = 0.14 + 0.42 * glow

# --- estrellas ---
ns = 650
sx = rng.uniform(0, W, ns)
sy = rng.uniform(0, H, ns)
ss = rng.uniform(0.2, 1.6, ns)
sa = rng.uniform(0.25, 0.95, ns)

# --- particulas de los discos ---
def disco(n, rmin, rmax):
    r = rmin + (rmax - rmin) * np.sqrt(rng.uniform(0, 1, n))
    th = rng.uniform(0, 2 * np.pi, n)
    return r, th

n = 1900
r1, th1 = disco(n, 60, 230)
r2, th2 = disco(n, 60, 230)
# colores: naranja para A, cian para B
col1 = np.zeros((n, 4)); col1[:, 0] = 1.0; col1[:, 1] = rng.uniform(0.35, 0.75, n); col1[:, 2] = 0.08
col1[:, 3] = rng.uniform(0.70, 1.0, n)
col2 = np.zeros((n, 4)); col2[:, 0] = 0.15; col2[:, 1] = rng.uniform(0.5, 0.85, n); col2[:, 2] = 1.0
col2[:, 3] = rng.uniform(0.70, 1.0, n)

fig = plt.figure(figsize=(W / 100, H / 100), dpi=100)
ax = fig.add_axes([0, 0, 1, 1])
ax.set_xlim(0, W); ax.set_ylim(0, H)
ax.set_axis_off()
fig.patch.set_facecolor("black")
ax.imshow(bg, extent=[0, W, 0, H], origin="lower", zorder=0)

def posiciones(t):
    if t < T_MERGE:
        u = t / T_MERGE
        sep = 470 * (1 - u ** 0.8) + 10
        ang = 2 * np.pi * (0.55 * u + 1.35 * u ** 2)
        x1, y1 = cx - sep / 2 * np.cos(ang), cy - sep / 2 * np.sin(ang)
        x2, y2 = cx + sep / 2 * np.cos(ang), cy + sep / 2 * np.sin(ang)
        return (x1, y1, x2, y2, u, ang)
    return (cx, cy, cx, cy, 1.0, 0.0)

for k in range(N):
    t = k / FPS
    for col in list(ax.collections):
        col.remove()
    for p in list(ax.patches):
        p.remove()
    x1, y1, x2, y2, u, ang = posiciones(t)
    ax.scatter(sx, sy, s=ss, c="white", alpha=sa, linewidths=0, zorder=1)

    if t < T_MERGE:
        # discos: giran mas rapido al acercarse
        w = 0.9 + 3.2 * u
        a1 = th1 + w * t * (120.0 / (r1 + 40))
        a2 = th2 - w * t * (120.0 / (r2 + 40))
        ax.scatter(x1 + r1 * np.cos(a1), y1 + r1 * np.sin(a1), s=5.5, c=col1, linewidths=0, zorder=3)
        ax.scatter(x2 + r2 * np.cos(a2), y2 + r2 * np.sin(a2), s=5.5, c=col2, linewidths=0, zorder=3)
        # halos
        ax.scatter([x1, x2], [y1, y2], s=5200, c=["#ff8a3d", "#4fc3ff"], alpha=0.28, linewidths=0, zorder=2)
        ax.add_patch(Circle((x1, y1), 55, color="black", zorder=5))
        ax.add_patch(Circle((x2, y2), 55, color="black", zorder=5))
        ax.add_patch(Circle((x1, y1), 62, fill=False, color="#ffb066", lw=6, alpha=1.0, zorder=6))
        ax.add_patch(Circle((x2, y2), 62, fill=False, color="#8fe3ff", lw=6, alpha=1.0, zorder=6))
    else:
        dt = t - T_MERGE
        # disco unico + anillos que se expanden
        w = 2.2
        a1 = th1 + w * t * (120.0 / (r1 + 40))
        a2 = th2 - w * t * (120.0 / (r2 + 40))
        ax.scatter(cx + r1 * np.cos(a1), cy + r1 * np.sin(a1), s=6.0, c=col1, linewidths=0, zorder=3)
        ax.scatter(cx + r2 * np.cos(a2), cy + r2 * np.sin(a2), s=6.0, c=col2, linewidths=0, zorder=3)
        ax.scatter([cx], [cy], s=12000, c="#fff2c8", alpha=max(0.0, 1.0 - dt * 1.1), linewidths=0, zorder=2)
        for j, rr in enumerate([120, 220, 340, 480]):
            rad = rr + dt * 260
            ax.add_patch(Circle((cx, cy), rad, fill=False, color="#9fd8ff",
                                lw=max(2.0, 8.0 - j * 1.2), alpha=max(0.0, 0.85 - dt * 0.2), zorder=4))
        ax.add_patch(Circle((cx, cy), 30, color="black", zorder=5))
        ax.add_patch(Circle((cx, cy), 33, fill=False, color="#ffd9a0", lw=2.6, alpha=0.95, zorder=6))

    fig.savefig(os.path.join(OUT, "f%04d.png" % k), dpi=100)
    if k % 30 == 0:
        print("frame %d/%d" % (k, N))

plt.close(fig)

cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
       "-framerate", str(FPS), "-i", os.path.join(OUT, "f%04d.png"),
       "-c:v", "libx264", "-preset", "medium", "-crf", "18",
       "-pix_fmt", "yuv420p", "-r", str(FPS), SALIDA]
subprocess.run(cmd, check=True)
dur = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", SALIDA],
                     capture_output=True, text=True).stdout.strip()
print("OK %s | %.1fs" % (SALIDA, float(dur or 0)))
