# buscar-clips.ps1 — Busca y descarga clips de Pixabay (API oficial de videos)
#
# Uso:
#   .\scripts\buscar-clips.ps1 -Query "muscle car" -Cantidad 5
#   .\scripts\buscar-clips.ps1 -Query "dodge challenger" -Cantidad 3 -SoloVertical
#
# La API key se toma, en este orden:
#   1) -Key "xxxx"
#   2) variable de entorno PIXABAY_API_KEY
#   3) archivo .pixabay.key en la raiz del proyecto

param(
  [Parameter(Mandatory=$true)][string]$Query,
  [int]$Cantidad = 5,
  [string]$Key,
  [string]$Salida = "03-clips",
  [int]$MinHeight = 720,
  [int]$AlturaMax = 1080,
  [switch]$SoloVertical
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

# 1) Resolver la API key
if (-not $Key) { $Key = $env:PIXABAY_API_KEY }
if (-not $Key) {
  $kf = Join-Path $root ".pixabay.key"
  if (Test-Path $kf) { $Key = (Get-Content $kf -Raw).Trim() }
}
if (-not $Key) { throw "Falta la API key. Usa -Key, la variable PIXABAY_API_KEY, o crea el archivo .pixabay.key" }

if (-not (Test-Path $Salida)) { New-Item -ItemType Directory -Force -Path $Salida | Out-Null }

# 2) Consultar la API
$q = [uri]::EscapeDataString($Query)
$url = "https://pixabay.com/api/videos/?key=$Key&q=$q&lang=en&per_page=50&safesearch=true&order=popular"
Write-Host "Buscando: $Query"

try {
  $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
} catch {
  throw "Error consultando Pixabay: $($_.Exception.Message)"
}

if ($resp.totalHits -eq 0) { Write-Host "Sin resultados para '$Query'."; return }

# 3) Filtrar y ordenar (vertical primero si se pide)
$hits = $resp.hits | Where-Object {
  $_.videos.medium.height -ge $MinHeight -or $_.videos.large.height -ge $MinHeight
}
if ($SoloVertical) {
  $hits = $hits | Where-Object { $_.videos.medium.height -gt $_.videos.medium.width }
}
$hits = $hits | Select-Object -First $Cantidad

if (-not $hits) { Write-Host "No hubo resultados que cumplan los filtros."; return }

# 4) Descargar la mejor version disponible de cada clip
$slug = ($Query -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLower()
$i = 0
$registros = @()
foreach ($h in $hits) {
  $i++
  # Elegir la mejor version que NO exceda AlturaMax (1080p por defecto, para ir rapido)
  $candidatos = @($h.videos.large, $h.videos.medium, $h.videos.small) | Where-Object { $_.url }
  $v = $candidatos | Where-Object { $_.height -le $AlturaMax } | Sort-Object height -Descending | Select-Object -First 1
  if (-not $v) { $v = $candidatos | Sort-Object height | Select-Object -First 1 }
  if (-not $v) { continue }

  $dest = Join-Path $Salida ("{0}-{1}.mp4" -f $slug, $i)
  Write-Host ("  [{0}/{1}] {2}x{3} -> {4}" -f $i, $hits.Count, $v.width, $v.height, (Split-Path $dest -Leaf))
  Invoke-WebRequest -Uri $v.url -OutFile $dest -TimeoutSec 120 | Out-Null

  $registros += [pscustomobject]@{
    archivo = (Split-Path $dest -Leaf)
    pixabay = $h.pageURL
    autor   = $h.user
    tamano  = ("{0}x{1}" -f $v.width, $v.height)
    duracion = $h.duration
  }
}

# 5) Guardar registro de fuentes (para créditos y trazabilidad)
$regFile = Join-Path $Salida ("_fuentes-{0}.txt" -f $slug)
$registros | Format-Table -AutoSize | Out-String | Set-Content -Path $regFile -Encoding UTF8
Write-Host "Descargados $($registros.Count) clips. Fuentes en $regFile"
