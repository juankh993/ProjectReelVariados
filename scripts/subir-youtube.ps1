# subir-youtube.ps1 — Sube un video a YouTube (usa el token de youtube-auth.ps1)
#
# Uso:
#   .\scripts\subir-youtube.ps1 -Video "06-salida/2026-11-07/mi-reel.mp4" `
#     -Titulo "Tu cuerpo brilla (y no lo sabias)" `
#     -Descripcion "..." -Tags "curiosidades,ciencia,shorts"
#
# Sube en PRIVADO por defecto: el video se publica recien cuando el dueño da el OK.

param(
  [Parameter(Mandatory=$true)][string]$Video,
  [Parameter(Mandatory=$true)][string]$Titulo,
  [string]$Descripcion = "",
  [string]$Tags = "curiosidades,ciencia,datos curiosos,shorts,educacion",
  [string]$Categoria = "27",               # 27 = Educacion | 28 = Ciencia y tecnologia
  [ValidateSet("public","unlisted","private")][string]$Privacidad = "private",
  [string]$Programar = "",                    # ISO 8601, ej 2026-10-21T12:30:00-05:00 (publica sola)
  [string]$Thumb = "",                        # miniatura 1080x1920 (jpg/png, <2 MB)
  [string]$TokenFile = ".youtube-token-VARIADO.json"   # canal fijo por script (no se cambia por flag)
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$tokenFile  = Join-Path $root $TokenFile
$clientFile = Join-Path $root ".youtube-client.json"
if (-not (Test-Path $tokenFile))  { throw ("Falta el token: " + $TokenFile + " (autoriza con scripts\youtube-auth.ps1 -Salida " + $TokenFile + ")") }
if (-not (Test-Path $clientFile)) { throw "Falta .youtube-client.json" }

$tok    = Get-Content $tokenFile -Raw | ConvertFrom-Json
$client = (Get-Content $clientFile -Raw | ConvertFrom-Json).installed

# 1) Refrescar el access token (duran 1 hora)
$body = @{
  client_id     = $client.client_id
  client_secret = $client.client_secret
  refresh_token = $tok.refresh_token
  grant_type    = "refresh_token"
}
$newTok = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $body -TimeoutSec 60
$access = $newTok.access_token
$tok.access_token = $access
$tok | ConvertTo-Json | Set-Content $tokenFile -Encoding UTF8

if (-not (Test-Path $Video)) { throw "No existe el video: $Video" }
$len = (Get-Item $Video).Length

# 2) Iniciar subida resumible
$statusObj = @{ privacyStatus = $(if ($Programar) { "private" } else { $Privacidad }); selfDeclaredMadeForKids = $false }
if ($Programar) { $statusObj.publishAt = $Programar }
$meta = @{
  snippet = @{ title = $Titulo; description = $Descripcion; tags = $Tags.Split(','); categoryId = $Categoria }
  status  = $statusObj
}
$jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($meta | ConvertTo-Json -Depth 5 -Compress))

$initHeaders = @{
  Authorization             = "Bearer $access"
  "X-Upload-Content-Type"   = "video/mp4"
  "X-Upload-Content-Length" = "$len"
}
$init = Invoke-WebRequest -Uri "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status" `
  -Method Post -Headers $initHeaders -ContentType "application/json; charset=UTF-8" `
  -Body $jsonBytes -TimeoutSec 60

$uploadUrl = $init.Headers.Location
if ($uploadUrl -is [array]) { $uploadUrl = $uploadUrl[0] }
if (-not $uploadUrl) { throw "No se obtuvo la URL de subida. Respuesta: $($init.StatusCode)" }

# 3) Subir los bytes
Write-Host ("Subiendo '{0}' ({1} MB)..." -f (Split-Path $Video -Leaf), [math]::Round($len/1MB,1))
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $Video))
$res = Invoke-RestMethod -Uri $uploadUrl -Method Put -Headers @{ Authorization = "Bearer $access" } `
  -ContentType "video/mp4" -Body $bytes -TimeoutSec 900

Write-Host "OK -> https://youtu.be/$($res.id)"

if ($Thumb) {
  if (-not (Test-Path $Thumb)) { Write-Host "AVISO: no existe la miniatura $Thumb"; exit 0 }
  try {
    $img = [IO.File]::ReadAllBytes((Resolve-Path $Thumb))
    $ct = if ($Thumb -match '\.png$') { "image/png" } else { "image/jpeg" }
    Invoke-RestMethod -Uri ("https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=" + $res.id + "&uploadType=media") `
      -Method Post -Headers @{ Authorization = "Bearer $access" } -ContentType $ct -Body $img -TimeoutSec 120 | Out-Null
    Write-Host "Miniatura OK"
  } catch {
    Write-Host ("AVISO: no se pudo poner la miniatura: " + $_.Exception.Message)
  }
}
