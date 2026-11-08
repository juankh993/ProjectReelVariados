# qa-reel.ps1 - Auditoria automatica de un reel de Furia Nation contra las reglas del canal
#
# Uso:
#   .\scripts\qa-reel.ps1 -Video "06-salida/2026-10-23/reel.mp4"
#   .\scripts\qa-reel.ps1 -Video "..." -MinDur 20 -MaxDur 25 -MotorEntra 14.8
#
# Salida: tabla de chequeos + OK / FALLA (exit code 0 / 1)

param(
  [Parameter(Mandatory=$true)][string]$Video,
  [double]$MinDur = 20,
  [double]$MaxDur = 25,
  [double]$DurTol = 0.6,          # tolerancia extra sobre MaxDur
  [double]$MinLufs = -15.5,
  [double]$MaxLufs = -13.0,
  [double]$MaxTruePeak = -1.0,
  [double]$MotorEntra = -1,       # opcional: segundo donde debe ENTRAR el motor
  [double]$MaxSilencioInicio = 1.0,
  [double]$MinCierre = 0.8,       # ultimos X segundos deben tener audio (motor de cierre)
  [switch]$Json
)

$ErrorActionPreference = "Continue"
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { $ff = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
$fp = Join-Path (Split-Path $ff) "ffprobe.exe"

if (-not (Test-Path $Video)) { Write-Output "FALLA: no existe el archivo $Video"; exit 1 }

function RMS([string]$f, [double]$desde, [double]$dur) {
  $o = (& $ff -hide_banner -ss $desde -t $dur -i $f -af volumedetect -f null NUL 2>&1 | Out-String)
  $m = [regex]::Match($o, 'mean_volume:\s*(-?[0-9.]+|-inf)')
  if (-not $m.Success) { return -999 }
  if ($m.Groups[1].Value -eq "-inf") { return -999 }
  return [double]$m.Groups[1].Value
}

# --- datos tecnicos ---
$dur = [double](& $fp -v error -show_entries format=duration -of csv=p=0 -- $Video)
$streams = (& $fp -v error -show_entries stream=codec_type,width,height -of csv=p=0 -- $Video | Out-String)
$tieneVideo = $streams -match "video"
$w = 0; $h = 0
if ($streams -match "video,[^,]*?,?(\d+),(\d+)") { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
if ($w -eq 0) {
  $wh = (& $fp -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 -- $Video)
  if ($wh -match "(\d+),(\d+)") { $w = [int]$Matches[1]; $h = [int]$Matches[2] }
}

# --- loudness ---
$sum = (& $ff -hide_banner -i $Video -af "loudnorm=print_format=summary" -f null NUL 2>&1 | Out-String)
$lufs = -99.0; $tp = 99.0
$mL = [regex]::Match($sum, 'Input Integrated:\s*(-?[0-9.]+|-inf)\s*LUFS')
if ($mL.Success -and $mL.Groups[1].Value -ne "-inf") { $lufs = [double]$mL.Groups[1].Value }
$mT = [regex]::Match($sum, 'Input True Peak:\s*(-?[0-9.]+|-inf)\s*dBTP')
if ($mT.Success -and $mT.Groups[1].Value -ne "-inf") { $tp = [double]$mT.Groups[1].Value }

# --- audio al inicio y al cierre ---
$rmsInicio = RMS $Video 0 $MaxSilencioInicio
$rmsCierre = RMS $Video ([math]::Max(0, $dur - $MinCierre)) $MinCierre
$rmsMedio  = RMS $Video ([math]::Floor($dur / 2)) 0.6

# --- golpe de motor (opcional) ---
$motorOk = $true; $motorDetalle = "-"
if ($MotorEntra -gt 0.05 -and $MotorEntra -lt $dur) {
  $antes = RMS $Video ([math]::Max(0, $MotorEntra - 0.7)) 0.6
  $despues = RMS $Video $MotorEntra 0.6
  $salto = $despues - $antes
  $motorOk = ($despues -gt -30) -and ($salto -gt 2)
  $motorDetalle = ("antes={0:N1} dB despues={1:N1} dB salto={2:+0.0;-0.0} dB" -f $antes, $despues, $salto)
}

# --- resultados ---
$checks = @()
function Add-Check($nombre, $ok, $detalle) {
  $script:checks += [pscustomobject]@{ Check = $nombre; Estado = $(if ($ok) { "OK" } else { "FALLA" }); Detalle = $detalle }
}

Add-Check "resolucion 1080x1920" ($w -eq 1080 -and $h -eq 1920) ("{0}x{1}" -f $w, $h)
Add-Check "duracion 20-25s" ($dur -ge $MinDur -and $dur -le ($MaxDur + $DurTol)) ("{0:N2}s" -f $dur)
Add-Check "audio en el primer segundo" ($rmsInicio -gt -50) ("{0:N1} dB" -f $rmsInicio)
Add-Check "cierre con sonido (no vacio)" ($rmsCierre -gt -40) ("{0:N1} dB en los ultimos {1:N1}s" -f $rmsCierre, $MinCierre)
Add-Check "loudness -15.5..-13 LUFS" ($lufs -ge $MinLufs -and $lufs -le $MaxLufs) ("{0:N1} LUFS" -f $lufs)
Add-Check "true peak <= -1.0 dBTP" ($tp -le $MaxTruePeak -and $tp -gt -99) ("{0:N1} dBTP" -f $tp)
Add-Check "audio continuo (mitad)" ($rmsMedio -gt -60) ("{0:N1} dB" -f $rmsMedio)
if ($MotorEntra -gt 0.05) { Add-Check ("entrada de motor en {0:N1}s" -f $MotorEntra) $motorOk $motorDetalle } else { Add-Check "motor desde el inicio" ($antes -gt -30) ("no aplica salto; nivel {0:N1} dB" -f $antes) }

$fallas = @($checks | Where-Object { $_.Estado -eq "FALLA" })

if ($Json) {
  [pscustomobject]@{
    video = $Video; duracion = [math]::Round($dur, 3); lufs = $lufs; truePeak = $tp
    w = $w; h = $h; ok = ($fallas.Count -eq 0); fallas = @($fallas | ForEach-Object { $_.Check })
  } | ConvertTo-Json -Depth 4
} else {
  Write-Output ("=== QA: " + (Split-Path $Video -Leaf))
  $checks | Format-Table -AutoSize | Out-String | Write-Output
  if ($fallas.Count -eq 0) { Write-Output "RESULTADO: OK" } else { Write-Output ("RESULTADO: FALLA (" + ($fallas.Check -join ", ") + ")") }
}

if ($fallas.Count -gt 0) { exit 1 } else { exit 0 }
