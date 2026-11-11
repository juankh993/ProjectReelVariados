# Canal variado — memoria del proyecto

> Proyecto **independiente** de Furia Nation (autos) y FrutiReels (frutas).
> Acá va contenido educativo: **curiosidades, ciencia, tecnología e historia**.

## Estado

- **Canal:** **Datoneta** (confirmado 2026-11-08). Español neutro, voz `es-MX-JorgeNeural`.
- **Branding:** mascota robot, paleta cian/violeta. Piezas en `assets/canal/`.
- **Formato:** Shorts de 45-60s, un solo dato que sorprenda.
- **Voz:** Gemini TTS `Iapetus` (3 días/semana) con respaldo automático a
  `es-MX-JorgeNeural` (edge-tts, gratis) si no hay cuota.
- **Motor de producción:** copiado y adaptado desde Furia Nation. **Funciona sin audio de motor**
  (`"sinMotor": true` en el JSON) y mezcla música de fondo (obligatoria al publicar).

## Reglas del canal (no negociables)

1. **Solo contenido seguro de licencias.** Prohibido Pinterest, TikTok, YouTube ajeno.
   Permitido: NASA/ESA (dominio público), Pexels, Pixabay, Unsplash, Wikimedia CC (con crédito),
   material propio.
2. **Un dato fuerte por video.** Nada de "5 datos" diluidos: uno solo, bien contado.
3. **Cierre con pregunta** (genera comentarios).
4. **Subtítulos siempre** (la mayoría mira sin sonido).
5. **Duración 45-60s.** Menos de 40s deja poco margen para explicar.
6. **Créditos obligatorios** cuando la fuente lo exige (Wikimedia, CC-BY): van en la descripción.
7. **Cada reel declara su fuente** en el JSON y se anota en `docs/LICENCIAS.md`.
8. **Ningún video se publica sin el OK del dueño.** Se sube siempre en privado
   (`subir-youtube.ps1` ya viene en privado por defecto) y el paso a público lo da él.
9. **Música de fondo obligatoria al publicar.** YouTube Audio Library (o Pixabay Music),
   al **12-16%**, sin batería marcada ni voz. Se registra el tema en `docs/LICENCIAS.md`.
10. **Ninguna imagen se repite más de 3 veces.** El render falla si se pasa; a las 3 avisa.
11. **CTA al final:** "DALE LIKE / COMENTA / SUSCRÍBETE" en pantalla los últimos 3 s.
    Es automático; `"cta": false` lo apaga y `"ctaDur"` cambia la duración.

## Pipeline (comandos)

```powershell
# 1) Render de un reel desde su JSON (incluye la música si el JSON la declara)
scripts\reel.ps1 -Config "01-guiones/2026-11-07/mi-reel.json"

# 2) Normalizar a -14 LUFS (obligatorio)
#    OJO: reel.ps1 ya hace 2 pasadas de loudnorm. Corré esto solo si el video
#    viene de otra herramienta (DaVinci, CapCut, etc.).
scripts\fix-loudness.ps1 -Entrada "06-salida/2026-11-07/mi-reel.mp4"

# 3) QA (duración, resolución, niveles, pico, reutilización de imágenes)
#    Con música NO uses -SinMusica (así también valida el cierre).
scripts\qa-reel.ps1 -Video "06-salida/2026-11-07/mi-reel.mp4" -Config "01-guiones/2026-11-07/mi-reel.json" -MinDur 45 -MaxDur 60

# 4) Copia ligera para el celular
#    (misma que usa Furia: scale=720:1280, crf 25)

# 5) Ver desde el teléfono
python scripts\servir.py "06-salida" 8860
```

## Formato del JSON (sin motor)

```json
{
  "id": "reel-01",
  "tipo": "fotos",
  "fecha": "2026-11-07",
  "salida": "reel-01.mp4",
  "subtitulos": true,
  "sinMotor": true,
  "vozMotor": "gemini",
  "voz": "Iapetus",
  "reusarVoz": true,
  "acento": "00C8FF",
  "gancho": "TU CUERPO BRILLA",
  "ganchoDur": 1.8,
  "vozEn": 0.3,
  "cola": 0.5,
  "ctaDur": 3.2,
  "limiteDuracion": 70,
  "a": {
    "vozTexto": "Lo que dice el guion...",
    "vozDecir": "Lo mismo pero escrito como se pronuncia (siglas, decimales).",
    "mostrar": { "ene a ese a": "NASA" },
    "visual": [
      { "tipo": "foto", "archivo": "03-visual/fotos/x.jpg", "dur": null, "zoom": "in" },
      { "tipo": "video", "archivo": "03-visual/clips/y.mp4", "desde": 0, "dur": 3, "zoom": "out" }
    ]
  },
  "musica": { "archivo": "05-musica/tema.mp3", "vol": 0.15 }
}
```

- `vozDecir` + `mostrar`: para que el TTS diga "NASA" y el subtítulo muestre NASA.
- `musica` es **obligatoria para publicar**; se repite en loop y se mezcla al 15% por defecto.
- `vozMotor`: `"gemini"` usa Gemini TTS (Iapetus, Kore, Puck…). Si se omite, usa edge-tts.
- `voz`: nombre de la voz. En Gemini: `Iapetus` (masculina, en-US). En edge: `es-MX-JorgeNeural`.
- `vozModelo`: modelo de Gemini TTS. Default `gemini-2.5-flash-preview-tts`.
- `vozAsr`: modelo de Whisper para alinear subtítulos (`base` por defecto, `small` más preciso).
- `vozFallback`: voz de edge si Gemini falla o no hay cuota. Default `es-MX-JorgeNeural`.
- `sinFallback`: `true` para que el reel falle en vez de cambiar de voz.
- `zoomSuave`: supersampling del Ken Burns (default **3**). Baja el temblor del paneo
  a 1/3 de pixel. `1` lo apaga; `4` es más suave pero más pesado. Solo aplica a fotos.
- `reusarVoz`: `true` reutiliza el MP3/SRT ya generado (no gasta cuota de Gemini).
- Gemini TTS **no devuelve tiempos por palabra**: `scripts/alinear-srt.py` los saca con
  faster-whisper y los alinea contra el guion.
- `gancho`: texto grande los primeros segundos (se achica solo si es muy largo).
- `acento`: color RRGGBB de la letra destacada de cada subtítulo. Default `00C8FF`
  (el cian del logo). Para volver al naranja: `"acento": "FFA500"`.
- `vozEn`: segundo en que entra la voz. **0.3s** es el default: si hay más silencio
  al principio, el espectador se va antes del dato. `cola`: 0.4-0.6s alcanza.
- **Planos:** para 50s usá 6-8 visuales de 5-8s. Un `dur: null` se come todo el resto,
  así que va uno solo y al final.

## Reglas de voz (aprendidas en Furia)

- **Siglas separadas**: `N A S A`, `A I`, `3 D`. Si se escriben juntas, el TTS las lee mal.
- **Números con decimales**: escribir "cuatro punto ocho" en `vozDecir` y mostrar `4.8`.
- edge-tts a veces falla con `NoAudioReceived` (transitorio): reintentar.

## Herramientas

| Script | Para qué |
|---|---|
| `reel.ps1` | Render completo desde JSON (visual + voz + subtítulos + gancho) |
| `tts-palabras.py` | Voz + SRT palabra por palabra |
| `qa-reel.ps1` | Auditoría automática |
| `fix-loudness.ps1` | Normaliza a −14 LUFS |
| `subir-youtube.ps1` | Sube el video (necesita token del canal nuevo) |
| `youtube-auth.ps1` | Autoriza el canal nuevo |
| `servir.py` | Sirve los videos por HTTP para verlos en el celular |
| `buscar-clips.ps1` / `buscar-fotos.ps1` | Búsqueda en Pixabay (`-SoloAutos` solo para autos) |
| `buscar-unsplash.ps1` | Búsqueda en Unsplash (`-SoloAutos` solo para autos) |
| `buscar-nasa.ps1` | Imágenes y videos de la NASA (dominio público, sin llave) |
| `marca-canal.ps1` | Genera avatar 1024×1024 y banner 2560×1440 con el nombre del canal |

## Pendiente

- [x] Confirmar nombre, idioma y tono del canal (**Datoneta**)
- [x] Adaptar el motor al canal (buscadores, subtítulos, QA, publicación)
- [x] Generar avatar, banner y watermark (`assets/canal/`)
- [x] Avatar y banner definitivos con el arte del robot
- [x] Primer tema ("Tu cuerpo brilla") publicado
- [x] Autorizar el canal de YouTube (token propio)
- [ ] Bajar 2-3 músicas de YouTube Audio Library (ver `05-musica/LEEME.md`)

## Panel web (rama `feature/panel-web`) — 2026-11-10
- `web/` es la aplicacion real: **Next.js 16 + React 19 + TypeScript** (front y backend juntos).
  `panel-web/` queda como prototipo estatico de referencia.
- Se levanta con `cd web; npm run dev` -> http://localhost:3000
- **Lo que ya funciona**: preview de video, formatos 9:16/16:9/1:1, biblioteca de activos,
  chat con IA (**gemini-3.5-flash**, con fallback local automatico), conexion OAuth de YouTube,
  estado del canal en vivo y **subida real** con titulo/descripcion/tags/visibilidad + miniatura.
- `gemini-flash-latest` da **503** seguido (alta demanda) y `gemini-2.5-flash` ya no esta disponible
  para cuentas nuevas: usar **`gemini-3.5-flash`** o `gemini-flash-lite-latest`.
- Next 16 trae `cacheComponents: true` por defecto: **no acepta** `export const runtime` ni
  `export const dynamic` en las rutas. Se desactivo en `next.config.ts`.
- Tokens en `web/data/tokens.json` (servidor, gitignored). Secrets en `web/.env.local`.
- Endpoints: `/api/chat`, `/api/youtube/{status,upload}`, `/api/youtube/oauth/{start,callback}`.
- Pendiente: conectores Instagram/TikTok/Facebook, calendario, render FFmpeg desde el panel y
  exportacion para CapCut (MP4 + SRT + audio + assets + manifest).
