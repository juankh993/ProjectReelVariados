# subir-youtube.ps1 — Sube un video a YouTube (usa el token de youtube-auth.ps1)
#
# Uso:
#   .\scripts\subir-youtube.ps1 -Video "06-salida/2026-10-14/1-challenger.mp4" `
#     -Titulo "797 HP: el muscle car mas brutal de Dodge" `
#     -Descripcion "..." -Tags "shorts,musclecars,hellcat" -Privacidad public

param(
  [Parameter(Mandatory=$true)][string]$Video,
  [Parameter(Mandatory=$true)][string]$Titulo,
  [string]$Descripcion = "",
  [string]$Tags = "shorts,musclecars,cars,v8",
  [string]$Categoria = "2",                 # 2 = Autos y vehiculos
  [ValidateSet("public","unlisted","private")][string]$Privacidad = "public",
  [string]$Programar = "",                    # ISO 8601, ej 2026-10-21T12:30:00-05:00 (publica sola)
  [string]$TokenFile = ".youtube-token-FURIA.json"   # canal fijo por script (no se cambia por flag)
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
