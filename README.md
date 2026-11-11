# Canal educativo — producción de Shorts

Canal de **ciencia, tecnología y curiosidades** en formato Short (45-60s).
Proyecto independiente de Furia Nation y FrutiReels.

## Arranque rápido

```powershell
# 1) render de un reel
scripts\reel.ps1 -Config "01-guiones/2026-11-07/mi-reel.json"

# 2) normalizar volumen
scripts\fix-loudness.ps1 -Entrada "06-salida/2026-11-07/mi-reel.mp4"

# 3) control de calidad
scripts\qa-reel.ps1 -Video "06-salida/2026-11-07/mi-reel.mp4" -MinDur 40 -MaxDur 65

# 4) ver en el celular
python scripts\servir.py "06-salida" 8860
```

## Documentación

- `AGENTS.md` — memoria del proyecto, reglas y pipeline
- `docs/ESTRATEGIA.md` — formato, pilares, primeros 10 temas
- `docs/MARCA.md` — paleta, tipografías y medidas de las piezas del canal
- `docs/CANAL.md` — identidad, descripción y configuración de YouTube
- `docs/PLANTILLA-VIDEO.md` — descripción, título y etiquetas de cada video
- `docs/VOZ.md` — comparación edge-tts vs Gemini TTS y cómo alinear subtítulos
- `docs/PUBLICADOS.md` — historial de videos publicados y retención
- `docs/METRICAS.md` — cómo se consultan las métricas y qué hacer con ellas
- `docs/LICENCIAS.md` — fuentes permitidas y registro de material

## Marca del canal

```powershell
scripts\marca-canal.ps1 -Nombre "Datoneta" -Fondo "assets\canal\_fuente\nebula-space-1.jpg"
```

Genera `assets\canal\avatar-<slug>.png` (1024×1024) y `banner-<slug>.png` (2560×1440),
con el nombre y la bajada del canal ya compuestos. La zona segura del banner (la que se ve
en celular) es 1546×423 centrada, y el script deja el texto ahí.

## Estructura

```
01-guiones/     JSON de cada reel
02-voz/         audios TTS generados
03-visual/      fotos y clips
04-audio/       (sonidos sueltos, si hiciera falta)
05-musica/      música de fondo
06-salida/      videos finales
07-publicados/  paquetes de publicación
assets/         branding
docs/           documentación
logs/           temporales
resources/      material fuente
scripts/        automatización
```