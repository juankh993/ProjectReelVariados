# MediaPilot — panel web (Next.js)

Panel de producción y publicación de video, agnóstico a la temática.
Front + backend en el mismo proyecto.

> Rama: `feature/panel-web`.

## Arrancar

```powershell
cd web
npm install          # solo la primera vez
npm run dev
```

Abrir `http://localhost:3000`.

## Variables de entorno

Copiar la plantilla y completar lo que se use:

```powershell
Copy-Item ..\.env.example .env.local
```

Mínimo para YouTube:

```ini
YOUTUBE_CLIENT_ID=...
YOUTUBE_CLIENT_SECRET=...
```

Opcional para el chat con IA:

```ini
GOOGLE_AI_KEY=...
GEMINI_MODELO=gemini-3.5-flash
```

`.env.local` y `data/` están en `.gitignore`.

## Qué funciona hoy

| Módulo | Estado |
|---|---|
| Panel responsive con navegación | ✅ |
| Carga de video + preview con scrubber | ✅ |
| Formatos 9:16 / 16:9 / 1:1 | ✅ |
| Biblioteca de activos del proyecto | ✅ |
| Chat con IA (Gemini 3.5 Flash + fallback local) | ✅ |
| Conexión de YouTube (OAuth2) | ✅ |
| Estado del canal en vivo (subs, videos, vistas) | ✅ |
| Subida real a YouTube con título, descripción, tags y visibilidad | ✅ |
| Miniatura al subir | ✅ |
| Instagram / TikTok / Facebook | ⏳ próxima fase |
| Calendario de publicación | ⏳ |
| Render FFmpeg desde el panel | ⏳ |
| Exportación para CapCut | ⏳ |

## Endpoints

| Ruta | Método | Qué hace |
|---|---|---|
| `/api/chat` | POST | Responde con Gemini; si falla, contesta local |
| `/api/youtube/status` | GET | Si hay cuenta conectada y datos del canal |
| `/api/youtube/oauth/start` | GET | Redirige a la pantalla de permiso de Google |
| `/api/youtube/oauth/callback` | GET | Canjea el código y guarda el refresh token |
| `/api/youtube/upload` | POST | Sube el video (multipart) y le pone miniatura |

## Seguridad

- Los tokens viven en `web/data/tokens.json`, **en el servidor**. Nunca llegan al navegador.
- La subida exige confirmación explícita en el panel.
- Los secrets se leen de `.env.local`, jamás desde el cliente.

## Estructura

```text
web/
├── app/
│   ├── page.tsx                 panel completo (cliente)
│   ├── globals.css
│   └── api/
│       ├── chat/route.ts
│       └── youtube/
│           ├── status/route.ts
│           ├── upload/route.ts
│           └── oauth/{start,callback}/route.ts
├── lib/
│   ├── config.ts                rutas y lectura de entorno
│   ├── tokens.ts                lectura/escritura del refresh token
│   └── youtube.ts               refresh, canal, subida resumible, miniatura
└── data/                        tokens y subidas (ignorado por git)
```

## Notas

- Next 16 con `cacheComponents` desactivado: las rutas leen y escriben archivos en cada request.
- `gemini-3.5-flash` es el modelo por defecto; si falla, prueba `gemini-flash-lite-latest`
  y por último responde con el modo local.
- La subida usa el endpoint resumible de YouTube (`uploadType=resumable`).
