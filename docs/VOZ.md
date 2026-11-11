# Voz — edge-tts vs Gemini TTS

## Probado el 2026-11-08

| | **edge-tts** (`es-MX-JorgeNeural`) | **Gemini TTS** (`Iapetus`) |
|---|---|---|
| Costo | Gratis, ilimitado | Free tier: ~10 pedidos/día |
| Acento | Español mexicano neutro | **en-US** (puede sonar con acento) |
| Subtítulos | WordBoundary exacto (nativo) | Whisper + alineación (~90-100%) |
| Latencia | ~2 s | ~14 s por cada 18 s de audio |
| Texto de 20 palabras | 8.66 s | 8.17 s |
| Marca de agua | No | SynthID (inaudible) |

## Qué se probó

- `gemini-2.5-flash-preview-tts` acepta la voz **Iapetus** y devuelve PCM 24 kHz mono.
- `gemini-3.8-flash-tts` está **sin cuota** en el plan free (10 pedidos/día agotados).
- La alineación de subtítulos con `faster-whisper base` (int8):
  - 18.7 s de audio → 6.2 s de transcripción, 100% de coincidencia.
  - Reel de prueba de 8.2 s → 90% de coincidencia, 20 palabras alineadas.
  - Primera descarga del modelo: ~4 min. Después carga en 4 s.

## Cómo se usa

En el JSON del reel:

```json
"vozMotor": "gemini",
"voz": "Iapetus",
"reusarVoz": true,
"subtitulos": true
```

- `reusarVoz: true` evita volver a llamar a la API si el MP3 y el SRT ya existen.
- Para volver a edge-tts, borrá `vozMotor` (o poné `"edge"`).
- Para más precisión en los subtítulos: `"vozAsr": "small"` (más lento).

## Limitaciones a tener en cuenta

1. **Iapetus es una voz en inglés.** Habla español, pero con acento estadounidense.
   Escuchala antes de decidir: para un canal en español, el acento puede restar.
2. **Cuota.** El plan free permite ~10 pedidos por día. Alcanza para 3 reels por semana,
   pero no para iterar mucho. **Si se agota, el reel sigue solo con Jorge** (`vozFallback`)
   y lo avisa en consola; el registro queda en `logs/tts-cuota.txt`.
3. **Un pedido por bloque.** Si el reel usa `versus` (dos voces), son dos pedidos.
4. **El audio lleva SynthID** (marca de agua inaudible de Google). No afecta a YouTube.
5. **No inventa tiempos.** Los subtítulos dependen de Whisper: revisá el SRT si el guion
   tiene siglas raras (NASA, siglas en inglés) o números.

## Recomendación

- Si el acento de Iapetus te gusta: usalo, suena más "humano" y menos robótico que edge.
- Si no: `es-MX-JorgeNeural` sigue siendo gratis, ilimitado y con subtítulos perfectos.

## Plan de voces (casi diario)

| Días | Voz |
|---|---|
| 3 por semana (los que elijas) | Gemini `Iapetus` |
| Resto | edge `es-MX-JorgeNeural` |

- En los reels de Gemini: `"vozMotor": "gemini"`, `"voz": "Iapetus"`.
- En los demás: no pongas `vozMotor` (usa Jorge).
- Si un día se agota la cuota, el sistema cae solo a Jorge: **el reel no se traba**.
- Para no gastar cuota al retocar el mismo video: `"reusarVoz": true`.
- Control de uso: `Get-Content logs\tts-cuota.txt`.
