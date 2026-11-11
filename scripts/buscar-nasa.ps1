# buscar-nasa.ps1 - Busca y descarga imagenes o videos de la NASA (dominio publico, sin API key)
#
# Uso:
#   .\scripts\buscar-nasa.ps1 -Query "carina nebula" -Cantidad 4
#   .\scripts\buscar-nasa.ps1 -Query "earth" -Tipo video -Cantidad 2
#
# Fuente: images-api.nasa.gov (NASA Image and Video Library). No requiere llave.
# Guarda la ficha de cada pieza en _fuentes-<query>.txt para el registro de LICENCIAS.
# Ojo: algunas piezas fueron aportadas por socios (ESA, JPL, universidades). Revisa la
# ficha del item antes de publicar; la mayoria es dominio publico de la NASA.

param(
  [Parameter(Mandatory=$true)][string]$Query,
  [int]$Cantidad = 4,
  [ValidateSet("image","video")][string]$Tipo = "image",
  [string]$Salida = "03-visual\nasa",
  [int]$MinAncho = 1200
)

$ErrorActionPreference = "Stop"
$api = "https://images-api.nasa.gov"

if (-not (Test-Path $Salida)) { New-Item -ItemType Directory -Force -Path $Salida | Out-Null }

$q = [uri]::EscapeDataString($Query)
$url = "$api/search?q=$q&media_type=$Tipo&page_size=40"
Write-Host "Buscando en NASA: $Query ($Tipo)"

try {
  $wc = New-Object System.Net.WebClient
  $bytes = $wc.DownloadData($url)
  $resp = ([System.Text.Encoding]::UTF8.GetString($bytes)) | ConvertFrom-Json
} catch {
  throw "Error consultando la NASA: $($_.Exception.Message)"
}

$items = @($resp.collection.items)
if ($items.Count -eq 0) { Write-Host "Sin resultados para '$Query'."; return }

$slug = ($Query -replace '[^a-zA-Z0-9]+', '-').Trim('-').ToLower()
$registros = @()
$i = 0
foreach ($it in $items) {
  if ($i -ge $Cantidad) { break }
  $d = @($it.data)[0]
  if (-not $d -or -not $d.nasa_id) { continue }

  # Lista de archivos reales de la pieza
  try { $asset = Invoke-RestMethod -Uri ("$api/asset/" + $d.nasa_id) -TimeoutSec 40 } catch { continue }
  $archivos = @($asset.collection.items | ForEach-Object { $_.href })
  if (-not $archivos) { continue }

  if ($Tipo -eq "video") {
    # preferir el mp4 mas grande disponible
    $cand = $archivos | Where-Object { $_ -match '\.mp4$' -and $_ -notmatch 'preview|thumb|small|mobile' }
    if (-not $cand) { continue }
    $elegido = $cand | Sort-Object { $_.Length } -Descending | Select-Object -First 1
    $ext = ".mp4"
  } else {
    # preferir jpg/png originales, descartar thumbnails
    $cand = $archivos | Where-Object { $_ -match '\.(jpg|jpeg|png)$' -and $_ -notmatch 'thumb|small|medium' }
    if (-not $cand) { $cand = $archivos | Where-Object { $_ -match '\.(jpg|jpeg|png)$' } }
    if (-not $cand) { continue }
    $elegido = $cand | Select-Object -First 1
    $ext = [IO.Path]::GetExtension($elegido)
  }

  $i++
  $dest = Join-Path $Salida ("{0}-{1}{2}" -f $slug, $i, $ext)
  Write-Host ("  [{0}/{1}] {2} -> {3}" -f $i, $Cantidad, $d.title, (Split-Path $dest -Leaf))
  try {
    Invoke-WebRequest -Uri $elegido -OutFile $dest -TimeoutSec 300 | Out-Null
  } catch {
    Write-Host ("    ! fallo la descarga: {0}" -f $_.Exception.Message)
    $i--
    continue
  }

  $registros += [pscustomobject]@{
    archivo = (Split-Path $dest -Leaf)
    titulo  = $d.title
    nasa_id = $d.nasa_id
    anio    = $d.date_created
    centro  = $d.center
    pagina  = "https://images.nasa.gov/details-$($d.nasa_id)"
    licencia = "NASA - dominio publico (revisar ficha)"
  }
  Start-Sleep -Milliseconds 300
}

$regFile = Join-Path $Salida ("_fuentes-{0}.txt" -f $slug)
$registros | Format-List | Out-String | Set-Content -Path $regFile -Encoding UTF8
Write-Host ("Descargados {0} archivos. Fuentes en {1}" -f $registros.Count, $regFile)
