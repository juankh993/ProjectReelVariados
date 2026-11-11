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

Modelo del chat (DeepSeek V4.1 Flash 1017 vía OpenRouter):

```ini
OPENROUTER_KEY=...
DEEPSEEK_MODELO=deepseek/deepseek-v4.1-flash-1017
```

Respaldo si OpenRouter falla:

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
| Chat con IA (DeepSeek V4.1 Flash 1017 via OpenRouter, fallback Gemini y local) | ✅ |
| Conexión de YouTube para CUALQUIER usuario (una cuenta por sesión) | ✅ |
| Estado del canal en vivo (subs, videos, vistas) | ✅ |
| Varios canales por usuario + desconectar | ✅ |
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

## Cómo conecta cada usuario su YouTube

1. El dueño del servidor crea un proyecto en **console.cloud.google.com**, habilita
   **YouTube Data API v3** y crea un **ID de cliente OAuth** de tipo *Aplicación de escritorio*
   (así localhost funciona sin registrar cada puerto).
2. Pega `YOUTUBE_CLIENT_ID` y `YOUTUBE_CLIENT_SECRET` en `web/.env.local`.
3. Cada usuario entra al panel, va a **Cuentas → Conectar canal** y autoriza con **su** cuenta.
4. Vuelve solo al panel y ya puede publicar en su canal.

Puntos clave:

- Cada navegador recibe una cookie de sesión (`mp_sid`): solo ve sus propios canales.
- Un usuario puede conectar **varios canales** y elegir el destino al publicar.
- **Desconectar** borra el token guardado de ese canal.
- Mientras la app de Google esté en modo *Prueba*, hay que agregar a cada persona en
  **Usuarios de prueba** (límite 100). Para uso abierto hay que publicar la app (verificación de Google).

## Notas

- Next 16 con `cacheComponents` desactivado: las rutas leen y escriben archivos en cada request.
- Chat: **DeepSeek V4.1 Flash 1017** vía OpenRouter. Si falla, Gemini 3.5 Flash; si también falla,
  responde el modo local.
- La subida usa el endpoint resumible de YouTube (`uploadType=resumable`).
