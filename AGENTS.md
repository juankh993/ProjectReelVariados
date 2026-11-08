# Canal variado — memoria del proyecto

> Proyecto **independiente** de Furia Nation (autos) y FrutiReels (frutas).
> Acá va contenido educativo: **ciencia, tecnología y curiosidades**.

## Estado

- **Canal:** por definir (nombre, idioma, tono).
- **Formato:** Shorts de 45-60s, un solo dato que sorprenda.
- **Voz:** `es-MX-JorgeNeural` por defecto (edge-tts, gratis).
- **Motor de producción:** copiado y adaptado desde Furia Nation. **Funciona sin audio de motor**
  (`"sinMotor": true` en el JSON) y acepta música de fondo opcional.

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

## Pipeline (comandos)

```powershell
# 1) Render de un reel desde su JSON
scripts\reel.ps1 -Config "01-guiones/2026-11-07/mi-reel.json"

# 2) Normalizar a -14 LUFS (obligatorio)
scripts\fix-loudness.ps1 -Entrada "06-salida/2026-11-07/mi-reel.mp4"

# 3) QA (duración, resolución, niveles, pico)
scripts\qa-reel.ps1 -Video "06-salida/2026-11-07/mi-reel.mp4" -MinDur 40 -MaxDur 65

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
  "gancho": "TU CUERPO BRILLA",
  "ganchoDur": 1.8,
  "vozEn": 1.0,
  "cola": 1.0,
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
  "musica": { "archivo": "05-musica/tema.mp3", "vol": 0.12 }
}
```

- `vozDecir` + `mostrar`: para que el TTS diga "NASA" y el subtítulo muestre NASA.
- `musica` es opcional; se repite en loop y se mezcla al 12% por defecto.
- `gancho`: texto grande los primeros segundos (se achica solo si es muy largo).

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
| `buscar-clips.ps1` / `buscar-fotos.ps1` | Búsqueda en Pixabay |
| `buscar-unsplash.ps1` | Búsqueda en Unsplash |

## Pendiente

- [ ] Definir nombre, idioma y tono del canal
- [ ] Elegir el primer tema y escribir el guion
- [ ] Autorizar el canal de YouTube (token propio)
- [ ] Definir la música de fondo (YouTube Audio Library / Pixabay Music)
