# DESARROLLO — bitácora del panel MediaPilot

> Documento vivo. Se actualiza en cada sesión de trabajo.
> Repo: `proyectoReelsVariado` · Rama del panel: `feature/panel-web`

---

## 1. Qué es

**MediaPilot** es un panel web para **crear y publicar video corto con IA**, sin depender
de una temática. Sirve para autos, ciencia, historia, comida o lo que el usuario quiera.

La idea no es subir videos hechos a mano: es **pedirle un reel al asistente y que el panel lo
produzca** (guion → voz → visuales → subtítulos → render → publicación).

---

## 2. Estado actual

| Módulo | Estado | Nota |
|---|---|---|
| Panel responsive (Estudio / Proyectos / Calendario / Cuentas) | ✅ | |
| Carga de video + preview con scrubber | ✅ | También recibe el render del panel |
| Formatos 9:16 · 16:9 · 1:1 | ✅ | |
| Biblioteca de activos del proyecto | ✅ | Solo nombres y tamaños por ahora |
| Chat con IA | ✅ | DeepSeek V4.1 Flash 1017 |
| Conexión de YouTube multi-usuario | ✅ | Una cuenta por sesión, varios canales |
| Estado del canal en vivo | ✅ | subs, videos, vistas, avatar |
| Subida real a YouTube + miniatura | ✅ | Endpoint resumible |
| **Generación del reel desde el panel** | ✅ | Plan del chat → eel.ps1 → MP4 en la preview |
| Conectores Instagram / TikTok / Facebook | ⏳ | Siguiente |
| Calendario de publicación | ⏳ | |
| Exportación CapCut | ⏳ | Último, a pedido del usuario |

---

## 3. Arquitectura

```text
web/
├── app/
│   ├── page.tsx                  panel completo (client component)
│   ├── globals.css               estilos
│   └── api/
│       ├── chat/route.ts         DeepSeek → Gemini → local
│       └── youtube/
│           ├── status/           lista de canales de la sesión
│           ├── upload/           subida resumible + miniatura
│           └── oauth/
│               ├── start/        redirige a Google
│               └── callback/     canjea código y guarda el canal
├── lib/
│   ├── config.ts                 rutas y lectura de entorno
│   ├── session.ts                cookie mp_sid
│   ├── accounts.ts               canales por sesión (JSON)
│   ├── oauth.ts                  redirect URI
│   └── youtube.ts                refresh, canal, subida, miniatura
└── data/                         accounts.json y subidas (gitignored)
```

### Modelo de datos de un canal

```json
{
  "id": "79800274c9ff6b44",
  "sessionId": "abc123...",
  "channelId": "UC_MqXv0irkUqYphEU8LXuOA",
  "title": "Datoneta",
  "thumbnail": "https://yt3.ggpht.com/...",
  "subscribers": "15",
  "videos": "4",
  "views": "1246",
  "refresh_token": "1//0g...",
  "access_token": "ya29...",
  "expires_at": 1760000000000,
  "createdAt": "2026-11-11T03:09:55.205Z",
  "shared": false
}
```

`sessionId: "*"` = canal del servidor, visible para todos (se usa para migrar el token viejo).

---

## 4. Decisiones técnicas y por qué

| Decisión | Motivo |
|---|---|
| **Next.js 16 (App Router)** | Front y backend en un solo proyecto, un solo `npm run dev`, deploy simple |
| **`cacheComponents: false`** | Las rutas leen/escriben archivos en cada request; Next 16 no permite `runtime` ni `dynamic` con cacheComponents activo |
| **Cookie `mp_sid` por navegador** | Cada usuario conecta su YouTube sin pisar el de otro |
| **Tokens en `web/data/`** | Nunca viajan al navegador; `data/` está en `.gitignore` |
| **DeepSeek V4.1 Flash 1017** vía OpenRouter | Es el modelo que se usa en la sesión; rápido y barato |
| **Cadena de respaldo** DeepSeek → Gemini → local | El chat nunca se queda mudo |
| **Subida resumible** (`uploadType=resumable`) | Permite archivos grandes y reintentos |
| **Migración automática del token viejo** | `data/tokens.json` se convierte en cuenta compartida la primera vez |

### Errores que ya nos costaron tiempo

1. **Next 16 + `cacheComponents`** → `export const runtime` y `export const dynamic` **no compilan**.
   Se desactivó `cacheComponents` en `next.config.ts`.
2. **`gemini-flash-latest` devuelve 503** con frecuencia y **`gemini-2.5-flash` ya no está
   disponible para cuentas nuevas** → modelo por defecto `gemini-3.5-flash`, con cadena de fallback.
3. **El endpoint de OpenCode Go exige `x-opencode-session`** y la clave de `auth.json` no sirve
   para consumo directo desde una app; **OpenRouter sí** con el modelo `deepseek/deepseek-v4.1-flash-1017`.

---

## 5. Cómo correr el panel

```powershell
cd web
npm install          # solo la primera vez
npm run dev
```

Abrir `http://localhost:3000`.

### Variables de entorno (`web/.env.local`)

```ini
APP_SECRET=...                              # firma de sesiones

YOUTUBE_CLIENT_ID=...                       # Google Cloud
YOUTUBE_CLIENT_SECRET=...
# YOUTUBE_REDIRECT_URI=http://localhost:3000/api/youtube/oauth/callback

OPENROUTER_KEY=sk-or-v1-...                 # chat principal
DEEPSEEK_MODELO=deepseek/deepseek-v4.1-flash-1017

GOOGLE_AI_KEY=...                           # respaldo del chat + TTS/Veo
GEMINI_MODELO=gemini-3.5-flash
```

`.env.local` y `data/` están en `.gitignore`. La plantilla pública es `.env.example`.

---

## 6. Conexión de YouTube (flujo actual)

```text
Usuario → "Conectar canal"
   → GET /api/youtube/oauth/start
   → Google (consent + select_account)
   → GET /api/youtube/oauth/callback
   → canjea código por refresh_token
   → lee el canal (channels?mine=true)
   → guarda la cuenta asociada a la cookie mp_sid
   → vuelve al panel con ?conectado=1
```

- El cliente OAuth debe ser de tipo **Aplicación de escritorio** para que `localhost` funcione
  en cualquier puerto sin registrar cada URI.
- `prompt=consent select_account` garantiza refresh token **y** que el usuario pueda elegir cuenta.
- Al publicar se elige el canal cuando hay más de uno.

---

## 7. Diseño del render (lo que sigue)

El panel **no reemplaza** el pipeline existente: lo **orquesta**.

```text
Chat: "quiero un reel sobre un creepypasta nocturno"
   ↓
La IA devuelve un PLAN estructurado (no solo prosa):
   {
     "titulo": "...",
     "gancho": "NO MIRES\nEL PORTERO",
     "vozTexto": "...",
     "escenas": [
       { "tipo": "foto", "archivo": "...", "dur": 6, "zoom": "in", "modo": "blurfill" },
       { "tipo": "video", "archivo": "...", "desde": 0, "dur": 8, "zoom": "out" }
     ],
     "musica": { "archivo": "05-musica/....mp3", "vol": 0.15 }
   }
   ↓
El panel escribe 01-guiones/<fecha>/<id>.json
   ↓
Ejecuta  scripts/reel.ps1 -Config <json>
   ↓
Ejecuta  scripts/fix-loudness.ps1 -Entrada <mp4>
   ↓
Preview muestra el MP4 generado
   ↓
"Publicar" → sube el render (no un archivo que subió el usuario)
```

### De dónde salen los visuales (lo que el proyecto ya tiene)

| Fuente | Script | Uso |
|---|---|---|
| NASA / ESA | `scripts/buscar-nasa.ps1` | Espacio, ciencia |
| Unsplash | `scripts/buscar-unsplash.ps1` | Fotos genéricas |
| Pixabay | `scripts/buscar-fotos.ps1`, `buscar-clips.ps1` | Fotos y clips |
| Propios | `03-visual/` | Material del usuario |
| Música | `05-musica/` | Pistas libres de reclamos |

**No hay generación de video con IA todavía** (falta modelo de video). Cuando se agregue,
se suma como una escena más: `{ "tipo": "ia", "prompt": "...", "dur": 5 }`.

### Lo que falta para cerrarlo

1. `POST /api/render` → recibe el plan, escribe el JSON y lanza `reel.ps1`.
2. Streaming del progreso (Server-Sent Events o polling de estado).
3. `GET /api/render/:id` → estado y ruta del MP4.
4. Botón "Generar reel" en el Estudio que use el plan que devolvió el chat.
5. Que el chat emita el plan en un bloque reconocible (` ```plan `) para parsearlo.

---

## 8. Bitácora

### 2026-11-10 — miniaturas y Kokoro (repo de Furia)

- Miniatura de Shorts: YouTube recorta las tarjetas al centro → **se genera vertical 1080x1920**.
- `scripts/miniatura.ps1` con formatos `vertical` (defecto), `cuadrado` y `horizontal`.
- Kokoro TTS medido: RTF 3,2-5,7 en el i3 (2-3 min por reel). Viable para 1 reel/día,
  no para lotes. Muestras en `06-salida/_muestras-voz/`.

### 2026-11-11 — panel: YouTube multi-usuario + DeepSeek

- Se creó `web/` (Next.js 16 + React 19).
- Chat con DeepSeek V4.1 Flash 1017 (OpenRouter), con respaldo Gemini y local.
- Conexión de YouTube por sesión, varios canales, desconectar, guía in-app.
- Verificado: OAuth genera la URL correcta de Google; el canal Datoneta se lee en vivo
  (15 subs · 4 videos · 1.246 vistas).
- **Pendiente de ajuste:** el chat respondía con un guion "listo para copiar" cuando el panel
  debe producir el reel. Se cambió el prompt para que entregue un **plan de producción** y
  explique que el render viene después.

---

## 9. Riesgos y pendientes

| Riesgo | Estado |
|---|---|
| Cuota de YouTube: **10.000 unidades/día**, y un `videos.insert` cuesta **1.600** → ~6 subidas/día | Documentar y avisar en la UI |
| App de Google en modo **Prueba**: máximo 100 usuarios de prueba | Ver `GOOGLE-CLOUD-PRODUCCION.md` |
| `web/data/` sin cifrar | Aceptable en local; en producción usar DB + cifrado |
| Sin autenticación de usuarios | Cualquiera con la URL crea su sesión. Hace falta login antes de exponerlo a internet |
| Render en Windows (PowerShell + FFmpeg) | El server tiene que correr en la máquina del usuario |
| Sin generación de video IA | Se resuelve cuando haya modelo de video |

---

## 10. Próximos pasos (orden acordado con el usuario)

1. **Conectores**: Instagram (ya probado en el repo de Furia), luego Facebook y TikTok.
2. **Render desde el panel**: plan del chat → `reel.ps1` → preview.
3. **Calendario**: programar publicaciones.
4. **Exportación CapCut**: al final.

### 2026-11-11 (cont.) — el chat pasa a producir PLANES, no guiones

- El usuario detecto que el chat devolvia un guion "listo para copiar" con marcas de tiempo,
  cuando el panel tiene que **producir el reel**, no entregar texto.
- Se reescribio el prompt del sistema: ahora conoce el producto (guion -> voz -> visuales ->
  subtitulos -> render -> publicacion), sabe que **no hay modelo de video IA** y que los visuales
  salen de NASA/Unsplash/Pixabay/Pexels + archivo propio.
- Cuando piden un reel, devuelve **un bloque ```plan con JSON**: titulo, gancho, vozTexto,
  duracion, escenas[{n,descripcion,busqueda,dur,movimiento}], musica y cierre.
- `extraerPlan()` lo detecta en el backend y lo devuelve en `plan`; la UI lo muestra como
  "PLAN DE PRODUCCION LISTO" con boton **Generar reel** (apagado hasta la fase de render).
- ⚠️ **max_tokens**: con 700 el JSON se cortaba a la mitad y no se detectaba el plan.
  Subido a **2000** en DeepSeek y Gemini.
- Flujo de trabajo elegido: **el plan usa `busqueda` en ingles**, no rutas de archivo: el renderer
  resuelve el material despues (asi el modelo no inventa archivos que no existen).

### 2026-11-11 (cont. 2) — RENDER IMPLEMENTADO

El chat ya no entrega solo el plan: el panel **produce el MP4**.

Flujo completo:

```text
Chat "quiero un reel sobre X"
  → DeepSeek devuelve ```plan (JSON)
  → tarjeta "PLAN DE PRODUCCION LISTO" + boton Generar reel
  → POST /api/render
      → escanea 03-visual/ y elige material por palabras clave (lib/material.ts)
      → escribe 01-guiones/<fecha>/<id>.json en el formato de reel.ps1
      → ejecuta scripts/reel.ps1 -Config ...   (voz edge + Ken Burns + subtitulos)
      → ejecuta scripts/fix-loudness.ps1       (-14 LUFS)
  → GET /api/render?id=... (polling cada 2,5s)
  → GET /api/render/file?id=... sirve el MP4
  → la preview lo muestra y "Publicar" lo sube a YouTube
```

Archivos nuevos:
- `web/lib/material.ts` — escanea `03-visual/`, puntua nombres contra la busqueda de cada escena.
- `web/lib/render.ts` — arma la config, lanza los scripts, guarda el estado del trabajo.
- `web/app/api/render/route.ts` — POST inicia / GET consulta estado.
- `web/app/api/render/file/route.ts` — entrega el MP4.

Decisiones:
- **El plan declara `busqueda`, no archivos.** El resolver elige material real; si no hay match,
  usa el primero libre (nunca queda una escena vacia).
- **Fix de duracion:** `reel.ps1` aborta si los planos fijos suman mas que la voz.
  Se estima la voz (13 caracteres/segundo) y se escalan los planos fijos al 62% de esa duracion;
  si igual falla, **se reintenta hasta 2 veces** con planos mas cortos (factor 0,55).
- **La salida usa el id del trabajo** (`<fecha>-<slug>-<random>.mp4`), asi no se pisan los renders.
- La musica se toma al azar de `05-musica/` al 14%.

Prueba real (2026-11-10):
- Plan de 4 escenas, 18s pedidos → **12,9s** (la voz manda).
- Salida 1080x1920, h264+aac, 7,7 MB, **-14,5 LUFS / -1,5 dBTP**.
- Gancho, subtitulos palabra por palabra y musica: OK.

Limitacion conocida: el resolver puede elegir capturas de infografias (con texto ya impreso)
porque solo mira nombres de archivo. Mejora pendiente: puntuar por contenido o por carpeta.
