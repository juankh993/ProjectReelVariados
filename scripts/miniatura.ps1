# miniatura.ps1 - Genera una miniatura 1080x1920 para un Short
#
# Uso:
#   .\scripts\miniatura.ps1 -Imagen "03-visual/fotos/x.jpg" -Texto "DOS LINEAS\nDE GANCHO" -Salida "06-salida/mini.jpg"
#   .\scripts\miniatura.ps1 -Video "06-salida/x.mp4" -Seg 2.5 -Texto "..." -Salida "mini.jpg"
#
# - Texto: 2 lineas separadas con \n. La ultima palabra va en cian.
# - -Acento "PALABRA": pinta esa palabra en cian en vez de la ultima.
# - -Y: altura del centro del texto (default 1350, tercio inferior).
# - Requiere el watermark en assets\canal\watermark-datoneta.png.

param(
  [Parameter(Mandatory=$true)][string]$Texto,
  [string]$Imagen = "",
  [string]$Video = "",
  [double]$Seg = 2.0,
  [string]$Salida = "",
  [double]$Y = 1350,
  [string]$Acento = ""
)

$ErrorActionPreference = "Stop"
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { throw "ffmpeg no esta en PATH" }
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function F([double]$v) { $v.ToString($inv) }

if (-not $Imagen -and -not $Video) { throw "Falta -Imagen o -Video" }
$wm = "assets\canal\watermark-datoneta.png"
if (-not (Test-Path $wm)) { throw "Falta el watermark: $wm" }

# salida por defecto
if (-not $Salida) {
  if ($Video) {
    $dir = Split-Path $Video
    $base = [IO.Path]::GetFileNameWithoutExtension($Video)
    $Salida = Join-Path $dir ("$base-mini.jpg")
  } else {
    New-Item -ItemType Directory -Force -Path "06-salida\miniaturas" | Out-Null
    $base = [IO.Path]::GetFileNameWithoutExtension($Imagen)
    $Salida = "06-salida\miniaturas\$base-mini.jpg"
  }
}
$outDir = Split-Path $Salida
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }

# texto -> ASS (2 lineas, ultima palabra en cian)
$t = $Texto.Trim().ToUpper($inv)
$t = $t -replace "\\n", "\N"
$t = $t -replace "`r?`n", "\N"
$lineas = $t -split "\\N"

if ($Acento) {
  $ac = $Acento.Trim().ToUpper($inv)
  $patron = [regex]::Escape($ac)
  for ($i = 0; $i -lt $lineas.Count; $i++) {
    $lineas[$i] = [regex]::Replace($lineas[$i], "\b$patron\b", "{\c&H00FFC800&}$ac{\c&H00FFFFFF&}")
  }
} else {
  $ult = $lineas[$lineas.Count - 1] -split " "
  if ($ult.Count -gt 0) {
    $ult[$ult.Count - 1] = "{\c&H00FFC800&}" + $ult[$ult.Count - 1] + "{\c&H00FFFFFF&}"
    $lineas[$lineas.Count - 1] = $ult -join " "
  }
}
$t = $lineas -join "\N"

$maxLen = 0
foreach ($ln in ($t -split "\\N")) {
  $limpio = $ln -replace "\{\\[^}]+\}", ""
  if ($limpio.Length -gt $maxLen) { $maxLen = $limpio.Length }
}
$size = [math]::Min(190, [math]::Floor(900 / ($maxLen * 0.55)))
if ($size -lt 70) { $size = 70 }

$assPath = "logs/_mini-" + [guid]::NewGuid().ToString("N").Substring(0,8) + ".ass"
$cab = @"
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Mini,Impact,$size,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,1,0,0,100,100,2,0,1,14,7,5,40,40,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"@
$evento = ("Dialogue: 0,0:00:00.00,0:00:10.00,Mini,,0,0,0,,{\pos(540," + [int]$Y + ")}" + $t)
[IO.File]::WriteAllText((Join-Path $PWD $assPath), ($cab + "`r`n" + $evento + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

# composicion
$in = if ($Imagen) { @("-i", $Imagen) } else { @("-ss", (F $Seg), "-i", $Video) }
$fc = "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920," +
      "eq=contrast=1.08:saturation=1.12,drawbox=x=0:y=0:w=iw:h=ih:color=black@0.15:t=fill[bg];" +
      "[bg][1:v]overlay=W-w-40:H-h-70[wm];" +
      "[wm]subtitles=$assPath,format=yuvj420p[out]"

& $ff -hide_banner -loglevel error -y @in -i $wm -filter_complex $fc -map "[out]" -frames:v 1 -q:v 2 $Salida
$ok = ($LASTEXITCODE -eq 0) -and (Test-Path $Salida)
Remove-Item $assPath -Force -ErrorAction SilentlyContinue
if (-not $ok) { throw "Fallo la miniatura" }
$kb = [math]::Round((Get-Item $Salida).Length / 1KB)
Write-Output ("miniatura: $Salida  ($kb KB)")
