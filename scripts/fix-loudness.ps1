# fix-loudness.ps1 - normaliza un MP4 a -14 LUFS con true peak controlado (2 pasadas + limitador)
param(
  [Parameter(Mandatory=$true)][string]$Entrada,
  [double]$Lufs = -14,
  [double]$Tp = -1.5
)
$ErrorActionPreference = "Continue"
$ff  = (Get-Command ffmpeg).Source
$fp  = (Get-Command ffprobe).Source

$json = (& $ff -hide_banner -i $Entrada -af "loudnorm=I=$Lufs`:TP=$Tp`:LRA=11:print_format=json" -f null NUL 2>&1 | Out-String)
$m = [regex]::Match($json, '(?s)\{.*\}')
if(-not $m.Success){ Write-Output "ERROR: no se pudo medir loudness"; exit 1 }
$d = $m.Value | ConvertFrom-Json
Write-Output ("medido: I=$($d.input_i) TP=$($d.input_tp) LRA=$($d.input_lra)")
$af = "loudnorm=I=$Lufs`:TP=$Tp`:LRA=11:measured_I=$($d.input_i):measured_TP=$($d.input_tp):measured_LRA=$($d.input_lra):measured_thresh=$($d.input_thresh):offset=$($d.target_offset):linear=true,alimiter=limit=0.70:level=false"

$tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), ("loud-" + [guid]::NewGuid().ToString('N') + ".m4a"))
& $ff -hide_banner -loglevel error -y -i $Entrada -af $af -c:a aac -b:a 192k -ar 48000 $tmp
if($LASTEXITCODE -ne 0){ Write-Output "ERROR al normalizar audio"; exit 1 }

$dir = Split-Path $Entrada
$name = [IO.Path]::GetFileNameWithoutExtension($Entrada)
$tmpOut = [IO.Path]::Combine($dir, "$name.tmp.mp4")
$out = [IO.Path]::Combine($dir, "$name.mp4")
& $ff -hide_banner -loglevel error -y -i $Entrada -i $tmp -map 0:v -map 1:a -c:v copy -c:a copy -shortest $tmpOut
if($LASTEXITCODE -ne 0){ Write-Output "ERROR al muxear"; exit 1 }
Move-Item -Force $tmpOut $out
Remove-Item -Force $tmp
Write-Output ("OK -> $out")
$sum = (& $ff -hide_banner -i $out -af "loudnorm=print_format=summary" -f null NUL 2>&1 | Out-String)
($sum -split "`n" | Where-Object { $_ -match "Input Integrated|Input True Peak" }) -join "`n"
