# marca-canal.ps1 - Genera el avatar y el banner del canal a partir del nombre.
#
# Uso:
#   .\scripts\marca-canal.ps1 -Nombre "Datoneta"
#   .\scripts\marca-canal.ps1 -Nombre "Datoneta" -Fondo "assets\canal\_fuente\nebula-space-1.jpg"
#
# Salida: assets\canal\avatar-<slug>.png (1024x1024) y banner-<slug>.png (2560x1440)
#
# Medidas oficiales de YouTube:
#   - Avatar: se sube a 1024x1024, se muestra en un circulo de 98px. Sin texto chico.
#   - Banner: 2560x1440. La zona segura (la que se ve en celular) es 1546x423 centrada.

param(
  [Parameter(Mandatory=$true)][string]$Nombre,
  [string]$Tagline = "¡Un mundo de curiosidades en segundos!",
  [string]$Pilares = "ciencia · tecnología · curiosidades",
  [string]$Fondo = "",
  [string]$Salida = "assets\canal"
)

$ErrorActionPreference = "Stop"
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { throw "ffmpeg no esta en PATH" }

$inv = [System.Globalization.CultureInfo]::InvariantCulture
$slug = ($Nombre.ToLower() -replace '[^a-z0-9]+', '-').Trim('-')
New-Item -ItemType Directory -Force -Path $Salida | Out-Null
New-Item -ItemType Directory -Force -Path "logs" | Out-Null

$titulo = $Nombre.ToUpper($inv)

# ---------- avatar 1024x1024 ----------
$avatar = Join-Path $Salida ("avatar-{0}.png" -f $slug)
$fAvatar = "format=rgba,vignette=angle=PI/3.2," +
  "drawtext=fontfile='C\:/Windows/Fonts/ariblk.ttf':text='?':fontsize=600:" +
  "fontcolor=0xFFFFFF:bordercolor=0x00C8FF:borderw=14:" +
  "shadowcolor=black@0.55:shadowx=0:shadowy=18:" +
  "x=(w-text_w)/2:y=(h-text_h)/2"
& $ff -hide_banner -loglevel error -y -f lavfi -i "color=c=0x101B3D:s=1024x1024" `
  -vf $fAvatar -frames:v 1 $avatar
if ($LASTEXITCODE -ne 0) { throw "Fallo el avatar" }

# ---------- banner 2560x1440 ----------
$banner = Join-Path $Salida ("banner-{0}.png" -f $slug)
$assPath = "logs/_marca-$slug.ass"

# tamano del titulo: se achica si el nombre es largo (max 1500px de ancho)
$size = [math]::Min(230, [math]::Floor(1500 / ($titulo.Length * 0.52)))
$mitad = [math]::Ceiling($titulo.Length / 2)
$t1 = $titulo.Substring(0, $mitad)
$t2 = $titulo.Substring($mitad)
$tituloColor = "{\c&H00FFFFFF&}$t1{\c&H00FFC800&}$t2"

$ass = @"
[Script Info]
ScriptType: v4.00+
PlayResX: 2560
PlayResY: 1440
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Titulo,Impact,$size,&H00FFFFFF,&H00FFFFFF,&H00000000,&H64000000,1,1,0,0,100,100,2,0,1,10,6,5,60,60,0,1
Style: Claro,Segoe UI Semibold,66,&H00F2F2F2,&H00F2F2F2,&H00000000,&H64000000,0,0,0,0,100,100,1,0,1,5,3,5,60,60,0,1
Style: Acento,Segoe UI Semibold,46,&H00FFC800,&H0000A5FF,&H00000000,&H64000000,0,0,0,0,100,100,1,0,1,4,2,5,60,60,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,0:00:10.00,Titulo,,0,0,0,,{\pos(1280,600)}$tituloColor
Dialogue: 0,0:00:00.00,0:00:10.00,Claro,,0,0,0,,{\pos(1280,770)}$Tagline
Dialogue: 0,0:00:00.00,0:00:10.00,Acento,,0,0,0,,{\pos(1280,865)}$($Pilares.ToUpper($inv))
"@
[IO.File]::WriteAllText((Join-Path $PWD $assPath), $ass, (New-Object System.Text.UTF8Encoding($false)))

if ($Fondo -and (Test-Path $Fondo)) {
  $entrada = @("-i", $Fondo)
  $prep = "scale=2560:1440:force_original_aspect_ratio=increase,crop=2560:1440,eq=brightness=-0.12:contrast=1.05:saturation=1.10"
  $sombra = "black@0.15"
} else {
  $entrada = @("-f", "lavfi", "-i", "color=c=0x0B1026:s=2560x1440")
  $prep = "vignette=angle=PI/4"
  $sombra = "black@0.25"
}

& $ff -hide_banner -loglevel error -y @entrada `
  -vf "$prep,drawbox=x=0:y=0:w=iw:h=ih:color=${sombra}:t=fill,subtitles=$assPath" `
  -frames:v 1 $banner
if ($LASTEXITCODE -ne 0) { throw "Fallo el banner" }

Remove-Item $assPath -Force -ErrorAction SilentlyContinue
Write-Output ("avatar: $avatar")
Write-Output ("banner: $banner")
Write-Output ("titulo: '{0}' a {1}px" -f $titulo, $size)
