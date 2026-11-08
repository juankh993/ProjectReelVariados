# verificar-canal.ps1 - Confirma a que canal apunta cada token de YouTube
#
# Metodo: sube un video privado de 1s con el token indicado, lee en que canal quedo
# (channelId/channelTitle), y lo intenta eliminar. Si no puede borrarlo, avisa para
# que lo borres a mano en Studio (queda privado).
#
# Uso:
#   .\scripts\verificar-canal.ps1              # ambos
#   .\scripts\verificar-canal.ps1 -Solo FURIA

param(
  [ValidateSet("ambos","FURIA","FRUTI")][string]$Solo = "ambos"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { throw "ffmpeg no esta en PATH" }

$esperados = @{
  "FURIA" = @{ file = ".youtube-token-FURIA.json"; id = "UCx7YGgjDt2XLs29BuRCnVXA"; nombre = "Furia Nation" }
  "FRUTI" = @{ file = ".youtube-token-FRUTI.json"; id = "UC3y_AQmvL8WqAbKW51ghMog"; nombre = "FrutiReels" }
}

$tmp = Join-Path $env:TEMP ("ytprobe-" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".mp4")
& $ff -hide_banner -loglevel error -y -f lavfi -i "color=c=black:s=320x240:d=1" -c:v libx264 -pix_fmt yuv420p $tmp

$lista = if ($Solo -eq "ambos") { @("FURIA","FRUTI") } else { @($Solo) }

foreach($k in $lista){
  $cfg = $esperados[$k]
  $tokFile = Join-Path $root $cfg.file
  if (-not (Test-Path $tokFile)) { Write-Output ("[$k] sin token: " + $cfg.file); continue }
  $tok   = Get-Content $tokFile -Raw | ConvertFrom-Json
  $cl    = (Get-Content (Join-Path $root ".youtube-client.json") -Raw | ConvertFrom-Json).installed
  $body  = @{ client_id=$cl.client_id; client_secret=$cl.client_secret; refresh_token=$tok.refresh_token; grant_type="refresh_token" }
  $acc   = Invoke-RestMethod -Method Post -Uri "https://oauth2.googleapis.com/token" -Body $body -TimeoutSec 60
  $auth  = "Bearer $($acc.access_token)"

  $meta = @{ snippet = @{ title = "probe $k"; description = "verificacion temporal" }
            status  = @{ privacyStatus = "private"; selfDeclaredMadeForKids = $false } } | ConvertTo-Json -Depth 5
  $jsonB = [System.Text.Encoding]::UTF8.GetBytes($meta)
  $mp4   = [System.IO.File]::ReadAllBytes($tmp)
  $initH = @{ Authorization = $auth; "X-Upload-Content-Type" = "video/mp4"; "X-Upload-Content-Length" = "$($mp4.Length)" }
  $r1 = Invoke-WebRequest -Uri "https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status" -Method Post -Headers $initH -ContentType "application/json; charset=UTF-8" -Body $jsonB -UseBasicParsing -TimeoutSec 60
  $u = $r1.Headers.Location; if ($u -is [array]) { $u = $u[0] }
  $v = Invoke-RestMethod -Uri $u -Method Put -Headers @{ Authorization = $auth } -ContentType "video/mp4" -Body $mp4 -TimeoutSec 300

  $ok = ($v.snippet.channelId -eq $cfg.id)
  Write-Output ("[$k] canal real: " + $v.snippet.channelTitle + " (" + $v.snippet.channelId + ")  |  esperado: " + $cfg.nombre + " (" + $cfg.id + ")")
  Write-Output ($(if($ok){ "     RESULTADO: CORRECTO" } else { "     RESULTADO: *** MAL ASIGNADO *** - no uses ese token para subir" }))
  try {
    Invoke-RestMethod -Uri ("https://www.googleapis.com/youtube/v3/videos?part=id&id=" + $v.id) -Method Delete -Headers @{ Authorization = $auth } -TimeoutSec 30 | Out-Null
    Write-Output ("     probe eliminado (" + $v.id + ")")
  } catch {
    Write-Output ("     probe quedo en el canal (" + $v.id + ") -> borralo en Studio (privado)")
  }
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue