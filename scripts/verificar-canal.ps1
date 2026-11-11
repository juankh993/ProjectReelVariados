# verificar-canal.ps1 - Confirma a que canal apunta cada token de YouTube
#
# Metodo: sube un video privado de 1s con el token indicado, lee en que canal quedo
# (channelId/channelTitle), y lo intenta eliminar. Si no puede borrarlo, avisa para
# que lo borres a mano en Studio (queda privado).
#
# Uso:
#   .\scripts\verificar-canal.ps1              # todos los que tengan token
#   .\scripts\verificar-canal.ps1 -Solo VARIADO

param(
  [ValidateSet("ambos","FURIA","FRUTI","VARIADO")][string]$Solo = "ambos"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ff) { throw "ffmpeg no esta en PATH" }

$esperados = @{
  "FURIA"   = @{ file = ".youtube-token-FURIA.json";   id = "UCx7YGgjDt2XLs29BuRCnVXA"; nombre = "Furia Nation" }
  "FRUTI"   = @{ file = ".youtube-token-FRUTI.json";   id = "UC3y_AQmvL8WqAbKW51ghMog"; nombre = "FrutiReels" }
  "VARIADO" = @{ file = ".youtube-token-VARIADO.json"; id = "UC_MqXv0irkUqYphEU8LXuOA"; nombre = "Datoneta" }
}

$tmp = Join-Path $env:TEMP ("ytprobe-" + [guid]::NewGuid().ToString("N").Substring(0,6) + ".mp4")
# Clip valido (3s, 720x1280, con audio silencioso): YouTube rechaza los de 1s/320x240.
& $ff -hide_banner -loglevel error -y `
  -f lavfi -i "color=c=0x0B1026:s=720x1280:d=3" `
  -f lavfi -i "anullsrc=r=48000:cl=stereo" `
  -shortest -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $tmp

$lista = if ($Solo -eq "ambos") { @("FURIA","FRUTI","VARIADO") } else { @($Solo) }

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

  $ok = if ($cfg.id) { ($v.snippet.channelId -eq $cfg.id) } else { $true }
  Write-Output ("[$k] canal real: " + $v.snippet.channelTitle + " (" + $v.snippet.channelId + ")  |  esperado: " + $cfg.nombre + " " + $(if ($cfg.id) { "(" + $cfg.id + ")" } else { "(id sin registrar: anotalo en verificar-canal.ps1)" }))
  if (-not $cfg.id) { Write-Output "     RESULTADO: token valido (canal sin id esperado registrado)" }
  else { Write-Output ($(if($ok){ "     RESULTADO: CORRECTO" } else { "     RESULTADO: *** MAL ASIGNADO *** - no uses ese token para subir" })) }
  try {
    Invoke-RestMethod -Uri ("https://www.googleapis.com/youtube/v3/videos?part=id&id=" + $v.id) -Method Delete -Headers @{ Authorization = $auth } -TimeoutSec 30 | Out-Null
    Write-Output ("     probe eliminado (" + $v.id + ")")
  } catch {
    Write-Output ("     probe quedo en el canal (" + $v.id + ") -> borralo en Studio (privado)")
    Write-Output ("     https://studio.youtube.com/video/" + $v.id + "/edit")
  }
}
Remove-Item $tmp -Force -ErrorAction SilentlyContinue