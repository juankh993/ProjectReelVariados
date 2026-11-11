# Marca — Datoneta

## Paleta

| Rol | Hex | Dónde se usa |
|---|---|---|
| Fondo profundo | `#0B1026` | fondos, banner, cierre |
| Primario (cian) | `#00C8FF` | ojos del robot, "neta", subtítulos, watermark |
| Acento cálido | `#FF8A00` | anillo del logo, detalles |
| Detalle | `#FFD400` | franja de la bajada, flechas |
| Texto | `#FFFFFF` | títulos y subtítulos |

Regla: **cian + un cálido**, nada más. Si aparece un tercer color fuerte, compite con la
voz y se ve "genérico de IA".

## Tipografía

| Uso | Fuente | Estilo |
|---|---|---|
| Títulos y subtítulos | **Impact** | mayúsculas, borde negro, sombra suave |
| Bajadas y textos de apoyo | **Segoe UI Semibold** | oración, sin borde |

## Piezas

| Pieza | Archivo | Medida | Notas |
|---|---|---|---|
| Avatar | `assets/canal/avatar-datoneta.png` | 1024×1024 | robot sin texto, probado a 98 px |
| Banner | `assets/canal/banner-datoneta.png` | 2560×1440 | arte propio + fondo desenfocado; texto en la zona segura |
| Watermark | `assets/canal/watermark-datoneta.png` | 150×150 | badge "D" circular, con transparencia |
| Lockup | `assets/canal/fuente/lockup.png` | 1281×1227 | robot + nombre, para cierres y miniaturas |
| Logo sin texto | `assets/canal/fuente/avatar-sin-texto.png` | 1289×1221 | fuente del avatar |

> `resources\marca-de-agua.jfif` **no es una marca de agua**: es una ilustración completa
> (robot en una ciudad). Para el watermark se usó el badge "D" del pecho del robot.

## Calidad de origen

- Avatar: 1289×1221 → 1024×1024. Suficiente.
- Banner: el original es 1222×607. Se recompuso a 2560×1440, pero **se ve suave** en
  escritorio. Si se genera una versión 16:9 a 2560×1440, se reemplaza sin tocar el texto.

## Reglas

1. **El avatar no lleva texto.** El nombre ya se muestra al lado; a 98 px el texto no se lee
   y el círculo lo recorta. Solo la cara del robot, centrada, con ~10% de aire.
2. **Nada importante fuera de la zona segura del banner.** En celular se ve solo la franja
   central de 1546×423.
3. **El acento de los subtítulos es cian** (`"acento": "00C8FF"` en el JSON del reel).
4. **El botón de play de YouTube no va en el arte**: es marca de la plataforma y sugiere
   una afiliación que no existe.

## Cómo se generan las piezas

```powershell
# avatar + banner de respaldo (fondo + tipografía, sin arte IA)
scripts\marca-canal.ps1 -Nombre "Datoneta" -Fondo "assets\canal\_fuente\nebula-space-1.jpg"

# cuando haya arte propio sin texto, se compone igual:
scripts\marca-canal.ps1 -Nombre "Datoneta" -Fondo "assets\canal\fuente\banner.png"
```
