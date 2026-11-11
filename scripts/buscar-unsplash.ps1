# buscar-unsplash.ps1 — Busca y descarga FOTOS de Unsplash (API oficial)
#
# Uso:
#   .\scripts\buscar-unsplash.ps1 -Query "nebula" -Cantidad 6
#   .\scripts\buscar-unsplash.ps1 -Query "cadillac cts-v" -Cantidad 8 -SoloAutos -TrackDownload
#
# Por defecto devuelve las fotos de la busqueda sin filtrar (sirve para cualquier tema).
# Con -SoloAutos exige que la descripcion/tags mencionen un auto.
#
# La API key (Access Key) se toma, en este orden: -Key, $env:UNSPLASH_ACCESS_KEY, o .unsplash.key
# El Secret va en .unsplash-secret.key (solo hace falta para flujos OAuth; la búsqueda NO lo usa).
#
# NOTAS
# - Límite: 50 peticiones/hora a api.unsplash.com (images.unsplash.com NO cuenta).
# - Guarda la atribución en 03-fotos\_fuentes-<query>.txt (obligatorio por las guías de la API).
# - -TrackDownload marca la descarga en Unsplash (guía de la API cuando se usa en producción).

param(
  [Parameter(Mandatory = $true)][string]$Query,
  [int]$Cantidad = 6,
  [string]$Salida = "03-fotos",
  [ValidateSet("all", "portrait", "landscape", "squarish")][string]$Orientacion = "all",
  [string]$KeyFile = ".unsplash.key",
  [string]$Key,
  [switch]$SoloAutos,
  [switch]$TrackDownload
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

# 1) Resolver la API key (Access Key)
$kf = if ([System.IO.Path]::IsPathRooted($KeyFile)) { $KeyFile } else { Join-Path $root $KeyFile }
if (-not $Key) {
  $Key = $env:UNSPLASH_ACCESS_KEY
}
if (-not $Key) {
  if (-not (Test-Path $kf)) { throw "Falta la API key de Unsplash. Crea $kf o define UNSPLASH_ACCESS_KEY." }
  $Key = (Get-Content $kf -Raw).Trim()
}
if (-not $Key) { throw "La API key de Unsplash está vacía: $kf" }

if (-not (Test-Path $Salida)) { New-Item -ItemType Directory -Force -Path $Salida | Out-Null }

# 2) Buscar
$q = [uri]::EscapeDataString($Query)
$url = "https://api.unsplash.com/search/photos?query=$q&per_page=30&order_by=relevant"
if ($Orientacion -ne "all") { $url += "&orientation=$Orientacion" }

Write-Host "Buscando en Unsplash: $Query (orientacion: $Orientacion)"
$headers = @{ "Authorization" = "Client-ID $Key"; "Accept-Version" = "v1" }

try {
  $resp = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 30
}
catch {
  throw "Error consultando Unsplash: $($_.Exception.Message)"
}

$results = $resp.results
Write-Host ("  Resultados: {0}" -f $resp.total)

if (-not $results) { Write-Host "Sin resultados."; return }

# 3) Filtro (opcional): que la foto sea de un auto (alt_description + tags)
if ($SoloAutos) {
  $carPattern = 'car|automobile|vehicle|muscle|coupe|sedan|classic|vintage|truck|van|road|parked|driving|engine|grille|wheel|hood|dashboard|interior|exhaust|wheel|mustang|chevrolet|ford|dodge|chrysler|cadillac|oldsmobile|pontiac|plymouth|buick|mercury|pontiac|camaro|challenger|charger|corvette|vette|vette|supercar|coupe|racing|auto show|garage'
  $validos = @()
  foreach ($p in $results) {
    $txt = (@($p.alt_description) + @($p.description) + @($p.tags | ForEach-Object { $_.title; $_.name })) -join " "
    if ($txt -and $txt -match $carPattern) { $validos += $p }
  }
  Write-Host ("  Validas como auto: {0} / {1}" -f $validos.Count, $results.Count)
  $results = $validos | Select-Object -First $Cantidad
  if (-not $results) { Write-Host "Ninguna foto paso la validacion de auto. Prueba otra busqueda."; return }
} else {
  $results = $results | Select-Object -First $Cantidad
}

# 4) Descargar
$slug = ($Query -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLower()
$registros = @()
$i = 0
foreach ($p in $results) {
  $i++
  $dest = Join-Path $Salida ("unsplash-{0}-{1}.jpg" -f $slug, $i)
  Write-Host ("  [{0}/{1}] {2} ({3}x{4}) -> {5}" -f $i, $results.Count, ($p.alt_description), $p.width, $p.height, (Split-Path $dest -Leaf))
  try {
    Invoke-WebRequest -Uri $p.urls.full -OutFile $dest -TimeoutSec 120 -Headers @{ "Accept" = "image/*" } | Out-Null
  }
  catch {
    Write-Host ("    ! fallo la descarga: {0}" -f $_.Exception.Message)
    continue
  }

  # Guía de la API: registrar el evento de descarga (solo en produccion)
  if ($TrackDownload -and $p.download_location) {
    try { Invoke-WebRequest -Uri $p.download_location -Headers $headers -TimeoutSec 20 | Out-Null } catch { }
  }

  $registros += [pscustomobject]@{
    archivo     = (Split-Path $dest -Leaf)
    titulo      = $p.alt_description
    fotografo   = $p.user.name
    usuario     = $p.user.username
    licencia    = "Unsplash License (uso libre, sin atribucion obligatoria)"
    pagina      = $p.links.html
    atribucion  = ("Photo by {0} on Unsplash {1}" -f $p.user.name, $p.links.html)
    medidas     = ("{0}x{1}" -f $p.width, $p.height)
  }
}

$regFile = Join-Path $Salida ("_fuentes-{0}.txt" -f $slug)
$registros | Format-List | Out-String | Set-Content -Path $regFile -Encoding UTF8
Write-Host ("Descargadas {0} fotos. Fuentes en {1}" -f $registros.Count, $regFile)
Write-Host ("Quedan ~{0} peticiones API esta hora (limite 50/h)." -f (50 - ($i + 1)))
