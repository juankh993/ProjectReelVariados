# Métricas

## Consulta

El token de Datoneta tiene que tener permisos de lectura. Se reautoriza **una vez**:

```powershell
scripts\youtube-auth.ps1 -Canal variado -Scope "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/yt-analytics.readonly"
```

Además, en Google Cloud tiene que estar habilitada la **YouTube Analytics API**
(console.cloud.google.com → APIs y servicios → habilitar).

Después, cuando haga falta:

```powershell
scripts\metricas-youtube.ps1 -Dias 28 -Max 10 -Guardar
```

`-Guardar` agrega un snapshot fechado a este archivo.

## Qué miramos

| Métrica | Qué dice | Objetivo inicial |
|---|---|---|
| **Retención %** | Si el video se ve completo o se descarta | ≥ 70% |
| **Duración media** | Segundos vistos por persona | ≥ 70% del video |
| **Vistas** | Alcance | Crecer semana a semana |
| **Subs por 1.000 vistas** | Si el canal convence | ≥ 2 |
| **Comentarios** | Si la pregunta del cierre funciona | ≥ 1 por 1.000 vistas |

## Cómo se decide el siguiente paso

- **Retención < 50%:** se descarta el tema y el formato. Se pasa a un pilar con retención
  comprobada (**espacio**) y a un formato de **simulación/demostración**.
- **Retención 50-70%:** se ajusta el gancho o el ritmo antes de repetir.
- **Retención ≥ 70%:** se mantiene el pilar y se duplica.

> Referencia: "El lugar más frío del universo" tiene 88%; "Tu cuerpo brilla", 32%.

> "Vistos vs. deslizados" es un dato de YouTube Studio que **no** está en la API.
> Se aproxima con el % de retención (`averageViewPercentage`).

## 2026-11-09 20:27 (manual, YouTube Studio)

- Vistas (28 días): **1.2 K** | Horas de reproducción: **6.9**
- Tu cuerpo brilla: 231 vistas · 9 likes · 3 comentarios (1 día 2 h)
- El lugar más frío del universo: 1 K vistas · 46 likes · 1 comentario (1 día)
- Los hipopótamos de Escobar: 229 vistas · 8 likes · 2 comentarios (1 h)

Estimación: 6.9 h / 1.2 K vistas ≈ 20 s por vista → ~40% de retención en videos de ~50 s.

## 2026-11-10 (API de datos)

- Suscriptores: **12** | videos: 3
- El lugar más frío: 1.228 vistas · 54 likes · 1 comentario
- Los hipopótamos de Escobar: 780 vistas · 24 likes · 4 comentarios
- Tu cuerpo brilla: 232 vistas · 10 likes · 3 comentarios
- Retención: la API de Analytics todavía devuelve 0 (retraso de 48-72 h).

## 2026-11-10 (retención)

- 14 suscriptores | 4 videos
- El lugar más frío: 1.238 vistas · **88% retención**
- Los hipopótamos: 838 vistas · retención pendiente
- Tu cuerpo brilla: 232 vistas · **32% retención**
- WiFi: 56 vistas · retención pendiente
- Regla: <50% se descarta el tema/formato; priorizar espacio + simulación.
