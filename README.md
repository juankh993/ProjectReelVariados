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
- `docs/LICENCIAS.md` — fuentes permitidas y registro de material

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