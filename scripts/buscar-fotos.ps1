# buscar-fotos.ps1 — Busca y descarga FOTOS de Pixabay (modelos especificos, consistentes)
#
# Uso:
#   .\scripts\buscar-fotos.ps1 -Query "nebula" -Cantidad 6
#   .\scripts\buscar-fotos.ps1 -Query "dodge challenger" -Cantidad 6 -SoloAutos -MismoAuto
#
# Por defecto devuelve las fotos de la busqueda sin filtrar (sirve para cualquier tema).
# Con -SoloAutos exige tags de auto; con -MismoAuto agrupa por autor para que el auto
# sea el mismo en todo el video (solo tiene sentido junto con -SoloAutos).
#
# La API key se toma, en este orden: -Key, $env:PIXABAY_API_KEY, o .pixabay.key

param(
  [Parameter(Mandatory=$true)][string]$Query,
  [int]$Cantidad = 6,
  [string]$Key,
  [string]$Salida = "03-fotos",
  [ValidateSet("all","horizontal","vertical")][string]$Orientacion = "all",
  [int]$MinWidth = 800,
  [switch]$SoloAutos,
  [switch]$MismoAuto
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

# Palabras que deben aparecer en los tags para considerar la foto como "de auto"
$carWords = @('car','cars','auto','autos','automobile','automotive','vehicle','vehicles',
  'muscle','muscle car','sports car','sportscar','supercar','coupe','hot rod','hotrod',
  'mustang','challenger','camaro','corvette','dodge','ford','chevrolet','chevy','shelby',
  'pontiac','plymouth','hemi','mopar','v8','engine','motor','wheel','race','racing',
  'classic car','road','drive','driving','highway','hellcat','gt500','charger')

# 1) Resolver la API key
if (-not $Key) { $Key = $env:PIXABAY_API_KEY }
if (-not $Key) {
  $kf = Join-Path $root ".pixabay.key"
  if (Test-Path $kf) { $Key = (Get-Content $kf -Raw).Trim() }
}
if (-not $Key) { throw "Falta la API key. Usa -Key, la variable PIXABAY_API_KEY, o crea el archivo .pixabay.key" }

if (-not (Test-Path $Salida)) { New-Item -ItemType Directory -Force -Path $Salida | Out-Null }

# 2) Consultar la API (FOTOS: endpoint /api/, lang=en). SIN filtro de color (contamina resultados).
$q = [uri]::EscapeDataString($Query)
$url = "https://pixabay.com/api/?key=$Key&q=$q&lang=en&image_type=photo&orientation=$Orientacion&safesearch=true&order=popular&per_page=50"
Write-Host "Buscando fotos: $Query (orientacion: $Orientacion)"

try {
  $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30
} catch {
  throw "Error consultando Pixabay: $($_.Exception.Message)"
}

if ($resp.totalHits -eq 0) { Write-Host "Sin resultados para '$Query'."; return }

# 3) Palabras distintivas del query (el MODELO). Se excluyen terminos genericos y marcas.
$genericos = @('car','cars','auto','autos','automobile','automotive','vehicle','vehicles','muscle',
  'classic','vintage','retro','old','sports','sport','american','usa','ss','coupe','super','hot',
  'rod','hotrod','motor','engine','race','racing','custom','street','road','drive','driving',
  'wallpaper','supercar','chevrolet','chevy','ford','dodge','plymouth','pontiac','buick',
  'oldsmobile','amc','chrysler','the','and','of','el','la','de')
$distintivas = @(($Query.ToLower() -split '\s+') | Where-Object { $_ -and ($genericos -notcontains $_) })

# 3b) Validar: por defecto alcanza con que la foto tenga tamano util.
#     Con -SoloAutos se exige tag de auto (y el modelo, si el query lo nombra).
$validas = $resp.hits | Where-Object {
  $tags = (" " + $_.tags.ToLower() + " ")
  $esAuto = if ($SoloAutos) { ($carWords | Where-Object { $tags -like "*$_*" }).Count -gt 0 } else { $true }
  $esModelo = if ($SoloAutos -and $distintivas.Count -gt 0) { ($distintivas | Where-Object { $tags -like "*$_*" }).Count -gt 0 } else { $true }
  $esAuto -and $esModelo
} | Where-Object { $_.largeImageURL -and ($_.imageWidth -ge $MinWidth -or $_.imageHeight -ge $MinWidth) }

if ($SoloAutos) {
  Write-Host ("  Resultados: {0} | validos como auto: {1}" -f $resp.hits.Count, $validas.Count)
} else {
  Write-Host ("  Resultados: {0} | validos: {1}" -f $resp.hits.Count, $validas.Count)
}
if (-not $validas) { Write-Host "Ninguna foto paso la validacion. Prueba otra busqueda."; return }

# 4) Consistencia ESTRICTA (solo autos): usar SOLO las fotos del autor mas prolífico
if ($SoloAutos -and $MismoAuto) {
  $grupos = $validas | Group-Object user | Sort-Object Count -Descending
  $top = $grupos[0]
  if ($top.Count -ge 3) {
    $hits = $top.Group | Select-Object -First $Cantidad
    Write-Host ("  MismoAuto: {0} fotos del autor '{1}' (un solo auto)" -f $hits.Count, $top.Name)
  } else {
    $hits = ($grupos | ForEach-Object { $_.Group }) | Select-Object -First $Cantidad
    Write-Host ("  MismoAuto: ningun autor tiene >=3 fotos; se mezclan autores (autos distintos).")
  }
} else {
  $hits = $validas | Select-Object -First $Cantidad
}

# 5) Limpiar descargas previas de esta busqueda y descargar
$slug = ($Query -replace '[^a-zA-Z0-9]+','-').Trim('-').ToLower()
Get-ChildItem $Salida -Filter "$slug-*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force

$i = 0
$registros = @()
foreach ($h in $hits) {
  $i++
  $dest = Join-Path $Salida ("{0}-{1}.jpg" -f $slug, $i)
  Write-Host ("  [{0}/{1}] {2}x{3} por {4} -> {5}" -f $i, $hits.Count, $h.imageWidth, $h.imageHeight, $h.user, (Split-Path $dest -Leaf))
  Invoke-WebRequest -Uri $h.largeImageURL -OutFile $dest -TimeoutSec 120 | Out-Null
  $registros += [pscustomobject]@{
    archivo  = (Split-Path $dest -Leaf)
    autor    = $h.user
    tamano   = ("{0}x{1}" -f $h.imageWidth, $h.imageHeight)
    pixabay  = $h.pageURL
  }
}

# 6) Registro de fuentes
$regFile = Join-Path $Salida ("_fuentes-{0}.txt" -f $slug)
$registros | Format-Table -AutoSize | Out-String | Set-Content -Path $regFile -Encoding UTF8
Write-Host "Descargadas $($registros.Count) fotos. Fuentes en $regFile"
