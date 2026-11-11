# metricas-youtube.ps1 - Resumen del canal y de los ultimos videos
#
# Uso:
#   .\scripts\metricas-youtube.ps1
#   .\scripts\metricas-youtube.ps1 -Dias 28 -Max 10 -Guardar
#
# Necesita un token con permisos de lectura:
#   youtube.upload + youtube.readonly + yt-analytics.readonly
# Si el token actual solo tiene upload, el script te dice como reautorizar.
#
# Metricas:
#   - Canal: suscriptores, vistas totales, cantidad de videos.
#   - Por video: vistas, likes, comentarios, duracion media vista y % de retencion.
#
# OJO: "vistos vs. deslizados" (el dato de Shorts de Studio) NO esta en la API.
# Se aproxima con el % de retencion (averageViewPercentage).

param(
  [string]$TokenFile = ".youtube-token-VARIADO.json",
  [int]$Dias = 28,
  [int]$Max = 10,
  [switch]$Guardar
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$tokFile = Join-Path $root $TokenFile
$clientFile = Join-Path $root ".youtube-client.json"

if (-not (Test-Path $tokFile)) { throw "Falta el token: $TokenFile" }
$tok = Get-Content $tokFile -Raw | ConvertFrom-Json
$cli = (Get-Content $clientFile -Raw | ConvertFrom-Json).installed

# 1) Refrescar el access token
$body = @{
  client_id     = $cli.client_id
  client_secret = $cli.client_secret
  refresh_token = $tok.refresh_token
  grant_type    = "refresh_token"
}
$acc = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -Body $body -TimeoutSec 60
$h = @{ Authorization = "Bearer $($acc.access_token)" }

function Reauth {
  Write-Output ""
  Write-Output "El token no tiene permiso para leer metricas. Reautoriza una vez con:"
  Write-Output '  scripts\youtube-auth.ps1 -Canal variado -Scope "https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube.readonly https://www.googleapis.com/auth/yt-analytics.readonly"'
  Write-Output ""
  Write-Output "Ademas, en Google Cloud tiene que estar habilitada la 'YouTube Analytics API'."
}

# 2) Canal
try {
  $ch = Invoke-RestMethod "https://www.googleapis.com/youtube/v3/channels?part=snippet,statistics,contentDetails&mine=true" -Headers $h -TimeoutSec 60
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 403) { Reauth; exit 2 }
  throw
}
if (-not $ch.items) { throw "La cuenta no tiene canal." }
$c = $ch.items[0]
Write-Output ("=== " + $c.snippet.title + "  (" + $c.id + ")")
Write-Output ("suscriptores: {0} | vistas: {1} | videos: {2}" -f $c.statistics.subscriberCount, $c.statistics.viewCount, $c.statistics.videoCount)

# 3) Ultimos videos
$uploads = $c.contentDetails.relatedPlaylists.uploads
$pl = Invoke-RestMethod "https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails&playlistId=$uploads&maxResults=50" -Headers $h -TimeoutSec 60
$ids = @($pl.items | ForEach-Object { $_.contentDetails.videoId })
if ($ids.Count -eq 0) { Write-Output "El canal todavia no tiene videos."; exit 0 }
$vids = Invoke-RestMethod ("https://www.googleapis.com/youtube/v3/videos?part=snippet,statistics,contentDetails&id=" + ($ids -join ",")) -Headers $h -TimeoutSec 60

# 4) Analitica: resumen del periodo y retencion por video
$start = (Get-Date).AddDays(-$Dias).ToString("yyyy-MM-dd")
$end = (Get-Date).ToString("yyyy-MM-dd")
$stats = @{}
$baseA = "https://youtubeanalytics.googleapis.com/v2/reports?ids=channel==MINE&startDate=$start&endDate=$end"

# 4a) resumen del periodo (sin dimensiones)
try {
  $repCh = Invoke-RestMethod ($baseA + "&metrics=views,estimatedMinutesWatched,averageViewDuration,subscribersGained,likes,comments") -Headers $h -TimeoutSec 60
  $rowsCh = @($repCh.rows)
  if ($rowsCh.Count -gt 0 -and $null -ne $rowsCh[0]) {
    $colsCh = @($repCh.columnHeaders | ForEach-Object { $_.name })
    $oCh = [ordered]@{}
    for ($i = 0; $i -lt $colsCh.Count; $i++) { $oCh[$colsCh[$i]] = $rowsCh[0][$i] }
    Write-Output ("periodo: {0} vistas | {1:N0} min vistos | dur. media {2:N0}s | +{3} subs" -f $oCh["views"], $oCh["estimatedMinutesWatched"], $oCh["averageViewDuration"], $oCh["subscribersGained"])
  } else {
    Write-Output "periodo: sin datos todavia (Analytics tarda 1-2 dias en publicarlos)"
  }
} catch {
  $code = $_.Exception.Response.StatusCode.value__
  if ($code -eq 403) {
    Write-Output "AVISO: sin permiso de YouTube Analytics; muestro solo los datos publicos."
    Write-Output "       Habilita 'YouTube Analytics API' en Google Cloud y reintenta:"
    Write-Output "       https://console.cloud.google.com/apis/library/youtubeanalytics.googleapis.com"
  }
  else { Write-Output ("AVISO analitica: " + $_.Exception.Message) }
}

# 4b) retencion por video (dimensions=video exige filters=video==ID)
foreach ($id in $ids) {
  try {
    $f = [uri]::EscapeDataString("video==$id")
    $u = $baseA + "&dimensions=video&filters=$f&metrics=views,estimatedMinutesWatched,averageViewDuration,averageViewPercentage"
    $rep = Invoke-RestMethod $u -Headers $h -TimeoutSec 60
    $rows = @($rep.rows)
    if ($rows.Count -gt 0 -and $null -ne $rows[0]) {
      $cols = @($rep.columnHeaders | ForEach-Object { $_.name })
      $o = [ordered]@{}
      for ($i = 0; $i -lt $cols.Count; $i++) { $o[$cols[$i]] = $rows[0][$i] }
      $stats[$id] = $o
    }
  } catch { }
}

$tabla = foreach ($v in $vids.items) {
  $s = $stats[$v.id]
  [pscustomobject]@{
    Video       = $v.snippet.title
    Publicado   = ([datetime]$v.snippet.publishedAt).ToString("yyyy-MM-dd")
    Vistas      = [int]$v.statistics.viewCount
    Likes       = [int]$v.statistics.likeCount
    Comentarios = [int]$v.statistics.commentCount
    Retencion   = if ($s) { "{0:N0}%" -f [double]$s["averageViewPercentage"] } else { "-" }
    DurMedia    = if ($s) { "{0:N0}s" -f [double]$s["averageViewDuration"] } else { "-" }
  }
}

$tabla | Sort-Object Vistas -Descending | Format-Table -AutoSize | Out-String | Write-Output
Write-Output ("ventana: ultimos {0} dias | videos en el canal: {1}" -f $Dias, $ids.Count)

if ($Guardar) {
  $md = Join-Path $root "docs\METRICAS.md"
  $fecha = Get-Date -Format "yyyy-MM-dd HH:mm"
  $lineas = @("", "## $fecha", "", "Canal: $($c.snippet.title) | subs: $($c.statistics.subscriberCount) | vistas: $($c.statistics.viewCount) | videos: $($c.statistics.videoCount)", "", "| Video | Publicado | Vistas | Likes | Comentarios | Retención | Dur. media |", "|---|---|---|---|---|---|---|")
  foreach ($t in ($tabla | Sort-Object Vistas -Descending)) {
    $lineas += ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f $t.Video, $t.Publicado, $t.Vistas, $t.Likes, $t.Comentarios, $t.Retencion, $t.DurMedia)
  }
  Add-Content -Path $md -Value ($lineas -join "`r`n") -Encoding UTF8
  Write-Output ("guardado en " + $md)
}
