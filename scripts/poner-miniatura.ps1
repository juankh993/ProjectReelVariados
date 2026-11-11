# poner-miniatura.ps1 - Cambia la miniatura de un video ya publicado
#
# Uso:
#   .\scripts\poner-miniatura.ps1 -VideoId "GUrZyxWZmaY" -Imagen "06-salida\2026-11-12\hipopotamos-mini.jpg"
#
# Necesita el mismo token que la subida (scope youtube.upload).

param(
  [Parameter(Mandatory=$true)][string]$VideoId,
  [Parameter(Mandatory=$true)][string]$Imagen,
  [string]$TokenFile = ".youtube-token-VARIADO.json"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$tokFile = Join-Path $root $TokenFile
$clientFile = Join-Path $root ".youtube-client.json"

if (-not (Test-Path $tokFile)) { throw "Falta el token: $TokenFile" }
if (-not (Test-Path $Imagen)) { throw "No existe la imagen: $Imagen" }

$tok = Get-Content $tokFile -Raw | ConvertFrom-Json
$cli = (Get-Content $clientFile -Raw | ConvertFrom-Json).installed
$body = @{
  client_id     = $cli.client_id
  client_secret = $cli.client_secret
  refresh_token = $tok.refresh_token
  grant_type    = "refresh_token"
}
$acc = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -Body $body -TimeoutSec 60

$img = [IO.File]::ReadAllBytes((Resolve-Path $Imagen))
$ct = if ($Imagen -match '\.png$') { "image/png" } else { "image/jpeg" }
$url = "https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=$VideoId&uploadType=media"

try {
  Invoke-RestMethod -Uri $url -Method Post -Headers @{ Authorization = "Bearer $($acc.access_token)" } `
    -ContentType $ct -Body $img -TimeoutSec 120 | Out-Null
  Write-Output ("Miniatura OK -> https://youtu.be/$VideoId")
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  Write-Output ("ERROR $code al poner la miniatura: " + $_.Exception.Message)
  exit 1
}
