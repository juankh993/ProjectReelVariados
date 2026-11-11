# youtube-auth.ps1 — Autoriza una vez (OAuth2) y guarda el token para subir videos
#
# Uso:
#   .\scripts\youtube-auth.ps1
#
# Abre el navegador, autorizas con tu cuenta de Google, y guarda el token en .youtube-token.json

param(
  [int]$Port = 8080,
  [string]$Scope = "https://www.googleapis.com/auth/youtube.upload",
  [ValidateSet("furia","fruti","variado")][string]$Canal = "variado",   # define el archivo destino
  [string]$Salida = "",                       # si se omite, usa .youtube-token-FURIA.json / -FRUTI.json
  [switch]$Manual,                            # navegador en otra maquina (usuario remoto)
  [string]$Callback = ""                      # URL del redirect (o el code) cuando se usa -Manual
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

$clientFile = Join-Path $root ".youtube-client.json"
if (-not (Test-Path $clientFile)) { throw "Falta .youtube-client.json (client_id y client_secret)." }
$client = (Get-Content $clientFile -Raw | ConvertFrom-Json).installed
$clientId = $client.client_id
$clientSecret = $client.client_secret
$redirect = "http://localhost:$Port/"

$authUrl = "https://accounts.google.com/o/oauth2/v2/auth?client_id=$clientId&redirect_uri=$([uri]::EscapeDataString($redirect))&response_type=code&scope=$([uri]::EscapeDataString($Scope))&access_type=offline&prompt=consent"

if ($Manual) {
  Write-Host ""
  Write-Host "=== MODO MANUAL ==="
  Write-Host "1) Abre esta URL en TU navegador:"
  Write-Host $authUrl
  Write-Host ""
  Write-Host "2) Acepta los permisos (si avisa que la app no esta verificada: Configuracion avanzada -> Continuar)."
  Write-Host "3) Copia la URL completa de la barra de direcciones (empieza con http://localhost:$Port/?code=...)."
  if (-not $Callback) { $Callback = Read-Host "Pega la URL (o solo el code)" }
  $mCode = [regex]::Match($Callback, "code=([^&#]+)")
  if ($mCode.Success) { $code = [uri]::UnescapeDataString($mCode.Groups[1].Value) } else { $code = $Callback.Trim() }
  if (-not $code) { throw "No se recibio el codigo." }
  $listener = $null
} else {
# Servidor local para capturar el codigo de autorizacion
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($redirect)
$listener.Start()

Write-Host "Abriendo el navegador para autorizar..."
Write-Host ""
Write-Host "Si el navegador no se abre, pega esta URL en tu navegador:"
Write-Host $authUrl
Write-Host ""
Start-Process $authUrl
Write-Host "Esperando la autorizacion (inicia sesion con la cuenta del canal y acepta)..."

$context = $listener.GetContext()
$code = $context.Request.QueryString["code"]
$errorMsg = $context.Request.QueryString["error"]

$html = if ($code) { "<h2>Autorizacion completada. Ya puedes cerrar esta pestana.</h2>" } else { "<h2>Error: $errorMsg</h2>" }
$buf = [System.Text.Encoding]::UTF8.GetBytes($html)
$context.Response.ContentType = "text/html; charset=utf-8"
$context.Response.OutputStream.Write($buf, 0, $buf.Length)
$context.Response.Close()
$listener.Stop()

if (-not $code) { throw "No se recibio el codigo de autorizacion ($errorMsg)." }
}

# Resolver archivo de token por canal si no se especifico manualmente
if (-not $Salida) {
  $Salida = switch ($Canal) {
    "fruti"   { ".youtube-token-FRUTI.json" }
    "furia"   { ".youtube-token-FURIA.json" }
    default   { ".youtube-token-VARIADO.json" }
  }
}

# Intercambiar el codigo por tokens
$body = @{
  code          = $code
  client_id     = $clientId
  client_secret = $clientSecret
  redirect_uri  = $redirect
  grant_type    = "authorization_code"
}
$tok = Invoke-RestMethod -Uri "https://oauth2.googleapis.com/token" -Method Post -Body $body -TimeoutSec 60
$tok | ConvertTo-Json | Set-Content (Join-Path $root $Salida) -Encoding UTF8

Write-Host "OK. Token guardado en $Salida"
Write-Host "Ya puedes subir videos con scripts\subir-youtube.ps1"
