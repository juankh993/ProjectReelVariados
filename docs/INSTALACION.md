# Instalación desde cero (clonar este repo)

Este documento es para alguien que clona el proyecto y necesita dejarlo funcionando.

## 1. Requisitos del sistema

| Herramienta | Versión | Verificar |
|---|---|---|
| **Python** | 3.12+ | `python --version` |
| **FFmpeg** | 6+ (probado en 9) | `ffmpeg -version` |
| **PowerShell** | 5.1 o 7 | `$PSVersionTable.PSVersion` |
| **git** | cualquiera | `git --version` |

Dependencia de Python:

```powershell
pip install edge-tts
```

`edge-tts` es lo único imprescindible: genera la **voz** y los **subtítulos**, gratis e ilimitado.

## 2. Qué NO viene en el repo

El `.gitignore` excluye a propósito:

- **Todas las llaves y tokens** (`*.key`, `.youtube-token*.json`, `.youtube-client.json`)
- **Todo el material pesado**: `03-visual/`, `04-audio/`, `05-musica/`, `06-salida/`,
  `resources/`, `logs/`, y los `.mp3` / `.srt` de `02-voz/`

Es decir: **clonás el código y los guiones, pero no los secretos ni los medios.**

## 3. Variables de entorno (opcional)

Los scripts aceptan la llave por **variable de entorno** en lugar del archivo `.key`.

| Variable | Script que la usa | Reemplaza a |
|---|---|---|
| `PIXABAY_API_KEY` | `buscar-clips.ps1`, `buscar-fotos.ps1` | `.pixabay.key` |
| `UNSPLASH_ACCESS_KEY` | `buscar-unsplash.ps1` | `.unsplash.key` |

```powershell
# solo esta sesión
$env:PIXABAY_API_KEY = "tu_key"

# permanente
[Environment]::SetEnvironmentVariable("PIXABAY_API_KEY", "tu_key", "User")
```

`LOCALAPPDATA` y `TEMP` ya vienen con Windows: no se configuran.

## 4. Archivos de llave

| Archivo | Contenido | Para qué | ¿Obligatorio? |
|---|---|---|---|
| `.pixabay.key` | la key pelada | Fotos y clips de fondo | ✅ Sí |
| `.unsplash.key` + `.unsplash-secret.key` | las keys | Fotos Unsplash | ❌ Opcional |
| `.google-ai.key` | la key | Imágenes IA / Gemini | ⬜ Recomendado |
| `.youtube.key` | API key de Google Cloud | Leer estadísticas del canal | ✅ Sí (para stats) |
| `.youtube-client.json` | `{"installed":{"client_id":"...","client_secret":"..."}}` | OAuth para subir videos | ✅ Sí (para subir) |
| `.youtube-token-<CANAL>.json` | lo genera `youtube-auth.ps1` | Token del canal | ✅ Para subir |

### Dónde se consigue cada una

| Key | Dónde |
|---|---|
| Pixabay | pixabay.com/api/docs (cuenta gratuita) |
| Unsplash | unsplash.com/developers |
| Google AI | aistudio.google.com/apikey |
| YouTube API key | console.cloud.google.com → habilitar "YouTube Data API v3" |
| YouTube OAuth | console.cloud.google.com → credenciales → "App de escritorio" → descargar JSON |

### Material visual: las fuentes gratuitas

| Fuente | Licencia | Cómo se obtiene |
|---|---|---|
| **NASA / ESA** | Dominio público | images.nasa.gov · esahubble.org |
| Pexels | Pexels License | pexels.com (descarga manual) |
| Pixabay | Pixabay License | `scripts\buscar-fotos.ps1` / `buscar-clips.ps1` |
| Unsplash | Unsplash License | `scripts\buscar-unsplash.ps1` |
| Wikimedia Commons | CC0 / CC BY / CC BY-SA | commons.wikimedia.org (**con crédito**) |

Música: **YouTube Audio Library** o **Pixabay Music** (nunca música con copyright).

### Autorizar YouTube

```powershell
scripts\youtube-auth.ps1 -Canal furia -Scope "https://www.googleapis.com/auth/youtube.force-ssl"
```

Se abre el navegador: hay que **elegir la cuenta correcta** del canal y aceptar.
Guarda el token en `.youtube-token-FURIA.json`.

> El parámetro `-Canal` define el nombre del archivo. Para otro canal, ajustar el script o pasar `-Salida`.

⚠️ Los tokens de YouTube caducan cada ~7 días (la app está en modo Testing). Cuando falle la subida,
volver a correr ese comando.

## 5. Verificar que quedó bien

```powershell
# buscar fotos (prueba de la key de Pixabay)
scripts\buscar-fotos.ps1 -Query "space" -Cantidad 2

# render de prueba (usa un PNG generado, no necesita material externo)
scripts\reel.ps1 -Config "01-guiones\2026-11-07\prueba.json"

# QA del resultado
scripts\qa-reel.ps1 -Video "06-salida\2026-11-07\prueba-sin-motor.mp4" -MinDur 4 -MaxDur 15
```

## 6. Cómo se hace un reel (resumen)

1. Escribir el JSON en `01-guiones/<fecha>/`.
2. Poner las imágenes/clips en `03-visual/` y la música en `05-musica/`.
3. Renderizar con `reel.ps1`.
4. Normalizar con `fix-loudness.ps1`.
5. Pasar el QA con `qa-reel.ps1`.
6. Anotar las fuentes en `docs/LICENCIAS.md`.

El formato del JSON está documentado en `AGENTS.md`.

## 7. Mapa de carpetas

```
01-guiones/      JSON de cada reel (SÍ versionado)
02-voz/          audio y subtítulos generados (NO versionado)
03-visual/       fotos y clips (NO versionado)
04-audio/        sonidos sueltos (NO versionado)
05-musica/       música de fondo (NO versionado)
06-salida/       videos finales (NO versionado)
07-publicados/   paquetes de publicación (SÍ versionado)
assets/          branding (SÍ versionado)
docs/            documentación (SÍ versionado)
scripts/         automatización (SÍ versionado)
resources/       material fuente (NO versionado)
logs/            temporales (NO versionado)
```
