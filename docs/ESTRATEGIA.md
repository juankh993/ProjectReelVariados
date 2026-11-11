# Estrategia — canal educativo (curiosidades, ciencia, tecnología e historia)

> Documento vivo. Se actualiza cuando se tomen decisiones (nombre, formato, temas).

## Nombre del canal

**Datoneta** (`@datoneta`), confirmado el 2026-11-08. Handle libre en YouTube.

Candidatos descartados: El Dato, Ciencia Curiosa, Datos Sueltos. Ocupados: Dato Mental,
Explicado en 60, Mente Curiosa, Curiosólogo, El Mundo en 60.

## La promesa

> **Cada video cuenta UN dato que sorprende, en menos de un minuto, con una imagen que lo hace
> inevitable.**

No es un canal de "datos curiosos" genéricos: es un canal donde cada video te deja pensando
"¿en serio?".

## Formato

| | |
|---|---|
| Duración | 45-60 segundos |
| Estructura | Gancho (2s) → dato → explicación corta → cierre con pregunta |
| Voz | Gemini TTS `Iapetus` (3 días/semana) o edge-tts `Jorge` |
| Visual | NASA/ESA + Pexels/Pixabay/Unsplash + imágenes IA + Ken Burns |
| Subtítulos | Sí, quemados |
| Música | **Obligatoria**: YouTube Audio Library o Pixabay Music, 12-16% |

## Los pilares (para rotar)

1. **Espacio** — NASA y ESA son dominio público y tienen material 4K
2. **Ciencia de lo cotidiano** — lo que usás todos los días y no sabés por qué funciona
3. **Tecnología** — cómo funciona algo que tenés en el bolsillo
4. **Cuerpo humano** — datos que dan un poco de vértigo
5. **Historia y personajes** — el dato que no sabías de un hecho o de alguien conocido
6. **Inventos** — de dónde salió algo que damos por obvio

## Historia y personajes

El canal es amplio: también cuenta historia, y eso incluye personajes y episodios
colombianos y latinoamericanos. Reglas para que funcione sin problemas:

1. **Un dato, no una biografía.** No es "la vida de X": es "el dato que no sabías de X".
2. **No glorificar.** Nada de apología a narcotraficantes ni a la violencia. Se cuenta el
   hecho con contexto y respeto por las víctimas.
3. **Sin imágenes gráficas** ni clips de series, películas o noticieros ajenos. Solo
   material con licencia (Wikimedia, archivo público, fotos propias).
4. **Verificar con dos fuentes** (prensa seria, libros, archivos). Si hay versiones en
   conflicto, decirlo en el guion.
5. **Cuidado con personas vivas**: nada que pueda leerse como difamación.

### Temas posibles (verificar cifras antes de escribir)

| Personaje / hecho | Ángulo "curioso" (no biografía) |
|---|---|
| Pablo Escobar | Los hipopótamos que llevó al Magdalena medio hoy son una especie invasora; el país discute qué hacer con ellos. |
| Luis Carlos Galán | La muerte de Galán y la "séptima papeleta" que terminó cambiando la Constitución de 1991. |
| La toma del Palacio de Justicia | El edificio que se reconstruyó igual, pero ya no es el mismo. |
| El Bogotazo | La ciudad que cambió en una tarde. |
| La bonanza bananera | El pueblo que tuvo cine, tren y energía antes que la capital. |

> Estos temas pueden atraer más comentarios, pero también más riesgo de moderación.
> Guion sobrio, sin morbo y con fuentes a la vista.

## Los primeros 10 temas

| # | Pilar | Tema | Gancho |
|---|---|---|---|
| 1 | Espacio | El lugar más frío del universo | Está a 5.000 años luz y es más frío que el vacío |
| 2 | Cuerpo | Tu cuerpo brilla | Emitís luz, solo que no la ves |
| 3 | Espacio | El día que duró 2 años | Ningún humano podría dormir así |
| 4 | Historia | El sonido más fuerte registrado | Sonó en 1883 y dio la vuelta al mundo 4 veces |
| 5 | Espacio | Por qué el espacio huele | Los astronautas dicen "a carne quemada" |
| 6 | Ciencia | El animal que no envejece | Puede volver a ser bebé |
| 7 | Ciencia | Cuánto pesa un rayo | Y por qué no te mata |
| 8 | Inventos | La máquina que lleva 200 años girando | Nadie sabe qué la mueve |
| 9 | Espacio | Marte tiene terremotos | Uno duró 90 minutos |
| 10 | Inventos | El invento más importante | No es la rueda ni el fuego |

## Estructura de un guion (plantilla)

```
[GANCHO en pantalla, 2s]
VOZ: "Esto que ves acá es [dato impactante]. Y no, no es lo que pensás."

[DESARROLLO, 30-40s]
VOZ: "Lo que pasa es que [explicación simple, sin tecnicismos].
Por eso [consecuencia que sorprende]."

[CIERRE, 8-10s]
VOZ: "[Remate]. ¿Vos lo sabías?"
```

## Regla de retención (2026-11-10)

- **< 50% de retención:** no se repite ese tema ni ese formato. Se cambia a un pilar con
  retención comprobada (**espacio**) y a un formato de **simulación o demostración**.
- **50-70%:** se ajusta el gancho/ritmo antes de repetir.
- **≥ 70%:** se mantiene y se duplica el pilar.

Referencia actual: "El lugar más frío del universo" retiene **88%**; "Tu cuerpo brilla", **32%**.
Por eso el próximo ciclo prioriza espacio + animación.

## Plan de arranque

| Fase | Meta |
|---|---|
| Arranque | 3 videos de prueba (uno por pilar) — hecho |
| **Experimento** | **1 video por día durante 14 días**, con un buffer de 5 videos |
| Corte | Si la retención cae por debajo de 55% en 5 videos seguidos, volver a 5 por semana |

**Regla de inversión:** no poner dinero hasta tener **20 videos gratis** y al menos uno por encima
de 1.000 vistas. Si eso no pasa, el formato necesita ajustes, no más presupuesto.

## Stack gratuito

| Etapa | Herramienta | Costo |
|---|---|---|
| Guion | ChatGPT / Gemini free | $0 |
| Voz | Gemini TTS (Iapetus) + edge-tts (Jorge) | $0 con cuota diaria |
| Visual base | **NASA / ESA** (dominio público) | $0 |
| B-roll | Pexels, Pixabay | $0 |
| Imágenes IA | Gemini, Leonardo free | $0 con límite |
| Animación | Ken Burns + parallax (pipeline propio) | $0 |
| Video IA real | Kling / Hailuo (créditos diarios) | $0 limitado |
| Edición | pipeline FFmpeg (o DaVinci Resolve) | $0 |
| Música | YouTube Audio Library, Pixabay Music | $0 |
| Miniaturas | Canva free / Photopea | $0 |

## Riesgos a cuidar

1. **Contenido IA de bajo esfuerzo**: YouTube penaliza desde 2025 los videos que son solo voz robótica
   sobre imágenes genéricas. El valor tiene que estar en el **guion** y en la **edición**.
2. **Música con copyright**: usar solo YouTube Audio Library o Pixabay Music.
3. **Datos falsos**: cada dato debe verificarse antes de publicar. Un error en un canal educativo
   destruye la credibilidad más rápido que en cualquier otro nicho.
4. **Temas sensibles** (narcotráfico, violencia política): contexto, sin glorificación y sin
   imágenes explícitas. Pueden limitar la monetización; el guion tiene que aportar, no morbo.
