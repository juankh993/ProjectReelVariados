# reel.ps1 - Renderizador generico de reels Furia Nation (guiado por JSON)
#
# Tipos: versus | fotos | footage
#
# Uso:
#   .\scripts\reel.ps1 -Config "01-guiones/2026-10-24/reel-01.json"
#   .\scripts\reel.ps1 -Config "..." -DryRun      (solo calcula tiempos y valida)
#
# El JSON define tipos de plano, motores, textos y timing. Ver specs/0004.

param(
  [Parameter(Mandatory=$true)][string]$Config,
  [switch]$DryRun
)

$ErrorActionPreference = "Continue"
$inv = [System.Globalization.CultureInfo]::InvariantCulture
function F([double]$v) { $v.ToString($inv) }

$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
$fp = Join-Path (Split-Path $ff) "ffprobe.exe"
function Dur([string]$p) { [double](& $fp -v error -show_entries format=duration -of csv=p=0 -- "$p") }

$cfg = Get-Content $Config -Raw -Encoding UTF8 | ConvertFrom-Json
$tipo = $cfg.tipo
if (-not $tipo) { throw "El JSON necesita 'tipo' (versus|fotos|footage)" }
Write-Output ("=== REEL: " + $cfg.id + "  [" + $tipo + "]")

# ---------- color de acento ----------
# "acento": "00C8FF" (RRGGBB). Pinta la letra destacada de cada subtitulo.
# Default: cian de la marca (el de la "neta" del logo y los ojos del robot).
$script:acentoAss = "&H00FFC800&"
if ($cfg.acento) {
  $hex = ("$($cfg.acento)" -replace '#','').ToUpper()
  if ($hex -match '^[0-9A-F]{6}$') {
    $script:acentoAss = ("&H00" + $hex.Substring(4,2) + $hex.Substring(2,2) + $hex.Substring(0,2) + "&")
  } else {
    Write-Output ("AVISO: acento invalido '" + $cfg.acento + "'; se usa el cian")
  }
}

# ---------- control de reutilizacion de imagenes ----------
foreach ($bloque in @($cfg.a, $cfg.b)) {
  if (-not $bloque -or -not $bloque.visual) { continue }
  $usos = @{}
  foreach ($p in @($bloque.visual)) {
    if (-not $p.archivo) { continue }
    $k = "$($p.archivo)"
    if ($usos.ContainsKey($k)) { $usos[$k]++ } else { $usos[$k] = 1 }
  }
  foreach ($k in $usos.Keys) {
    if ($usos[$k] -gt 3) { throw ("Imagen usada {0} veces (maximo 3): {1}" -f $usos[$k], $k) }
    elseif ($usos[$k] -gt 2) { Write-Output ("AVISO: imagen usada {0} veces: {1}" -f $usos[$k], $k) }
  }
}

# ---------- voz ----------
function AsegurarVoz($bloque, [string]$sufijo) {
  if ($bloque.vozArchivo -and (Test-Path $bloque.vozArchivo)) { return $bloque.vozArchivo }
  if (-not $bloque.vozTexto) { throw "Falta vozTexto o vozArchivo en el bloque $sufijo" }
  $out = "02-voz/$($cfg.id)-$sufijo.mp3"
  $srt = "02-voz/$($cfg.id)-$sufijo.srt"
  # Reuso opcional: "reusarVoz": true evita volver a gastar cuota de Gemini.
  if ($cfg.reusarVoz -and (Test-Path $out) -and ((-not $cfg.subtitulos) -or (Test-Path $srt))) {
    Write-Host ("  reuso de voz: " + $out)
    return $out
  }
  $txt = "logs/_voz-$($cfg.id)-$sufijo.txt"
  [IO.File]::WriteAllText((Join-Path $PWD $txt), $bloque.vozTexto, (New-Object System.Text.UTF8Encoding($false)))
  $esGemini = ("$($cfg.vozMotor)" -eq "gemini")
  $voz = if ($cfg.voz) { $cfg.voz } else { if ($esGemini) { "Iapetus" } else { "es-MX-JorgeNeural" } }
  # "vozDecir" = lo que el TTS pronuncia (siglas/decimales escritos como se leen).
  # "mostrar"  = mapa "frase hablada" -> "texto en pantalla" para los subtitulos.
  $mapa = $null
  if ($bloque.vozDecir -or $bloque.mostrar) {
    $mapa = [ordered]@{}
    if ($bloque.vozDecir) { $mapa["decir"] = $bloque.vozDecir }
    if ($bloque.mostrar) { $mapa["mostrar"] = $bloque.mostrar }
    $mapaJson = "logs/_voz-$($cfg.id)-$sufijo.json"
    [IO.File]::WriteAllText((Join-Path $PWD $mapaJson), ($mapa | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
  }
  # Texto que se sintetiza: vozDecir si existe, si no vozTexto.
  $fuente = $txt
  if ($bloque.vozDecir) {
    $txtDecir = "logs/_decir-$($cfg.id)-$sufijo.txt"
    [IO.File]::WriteAllText((Join-Path $PWD $txtDecir), $bloque.vozDecir, (New-Object System.Text.UTF8Encoding($false)))
    $fuente = $txtDecir
  }
  $usarGemini = $esGemini
  $vozEdge = if ($cfg.vozFallback) { $cfg.vozFallback } else { "es-MX-JorgeNeural" }

  if ($usarGemini) {
    # Gemini TTS: sintetiza el audio y despues alinea el SRT con Whisper.
    $modelo = if ($cfg.vozModelo) { $cfg.vozModelo } else { "gemini-2.5-flash-preview-tts" }
    $g = (& python scripts/gemini-tts.py $fuente $voz $out $modelo 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
    if ($code -ne 0 -or -not (Test-Path $out)) {
      if ($cfg.sinFallback) { throw ("Gemini TTS fallo (codigo $code). " + $g) }
      $motivo = if ($code -eq 2) { "sin cuota" } else { "error $code" }
      Write-Host ("  AVISO: Gemini TTS $motivo -> se usa " + $vozEdge)
      $usarGemini = $false
      Remove-Item $out -Force -ErrorAction SilentlyContinue
      Remove-Item $srt -Force -ErrorAction SilentlyContinue
    } elseif ($cfg.subtitulos) {
      $argMapa = if ($mapa) { $mapaJson } else { "-" }
      $modeloAsr = if ($cfg.vozAsr) { $cfg.vozAsr } else { "base" }
      $ali = (& python scripts/alinear-srt.py $out $fuente $srt $argMapa $modeloAsr | Out-String).Trim()
      Write-Host ("  " + $ali)
      if (-not (Test-Path $srt)) {
        if ($cfg.sinFallback) { throw "No se pudo alinear el SRT de $out" }
        Write-Host "  AVISO: no se pudo alinear el SRT -> se regenera con edge-tts"
        $usarGemini = $false
        Remove-Item $out -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if (-not $usarGemini) {
    if ($cfg.subtitulos) {
      $argMapa = if ($mapa) { $mapaJson } else { "-" }
      & python scripts/tts-palabras.py $fuente $vozEdge $out $srt $argMapa | Out-Null
    } else {
      & python -m edge_tts --voice $vozEdge --file $fuente --write-media $out | Out-Null
    }
  }
  if (-not (Test-Path $out)) { throw "El TTS no genero $out" }
  return $out
}

# ---------- subtitulos (palabra por palabra, estilo referencia) ----------
function Tiempo-Ass([double]$seg) {
  $h = [math]::Floor($seg / 3600)
  $m = [math]::Floor(($seg % 3600) / 60)
  $s = [math]::Floor($seg % 60)
  $cs = [math]::Round(($seg - [math]::Floor($seg)) * 100)
  if ($cs -ge 100) { $cs = 99 }
  return ("{0}:{1:00}:{2:00}.{3:00}" -f $h, $m, $s, $cs)
}

function Srt2Ass([string]$srtPath, [string]$assPath, [double]$offsetSeg) {
  $raw = Get-Content $srtPath -Raw -Encoding UTF8
  $bloques = [regex]::Split($raw, "(\r?\n){2,}") | Where-Object { $_ -match "-->" }
  $eventos = @()
  foreach ($b in $bloques) {
    $lineas = $b -split "\r?\n"
    $tl = ($lineas | Where-Object { $_ -match "-->" } | Select-Object -First 1)
    if (-not $tl) { continue }
    $m = [regex]::Match($tl, "(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)")
    if (-not $m.Success) { continue }
    $ini = [int]$m.Groups[1].Value*3600 + [int]$m.Groups[2].Value*60 + [int]$m.Groups[3].Value + [int]$m.Groups[4].Value/1000.0
    $fin = [int]$m.Groups[5].Value*3600 + [int]$m.Groups[6].Value*60 + [int]$m.Groups[7].Value + [int]$m.Groups[8].Value/1000.0
    $idxT = -1
    for ($q = 0; $q -lt $lineas.Count; $q++) { if ($lineas[$q] -match "-->") { $idxT = $q; break } }
    if ($idxT -lt 0 -or $idxT + 1 -ge $lineas.Count) { continue }
    $texto = ($lineas[($idxT + 1)..($lineas.Count - 1)] -join " ").Trim()
    if (-not $texto) { continue }
    $texto = $texto.Trim().ToUpper()
    # una letra en naranja: primera vocal acentuada, si no la letra central
    $acentos = [regex]::Matches($texto, "[\u00C0-\u00FF]")
    if ($acentos.Count -gt 0) { $pos = $acentos[0].Index }
    else {
      $letras = [regex]::Matches($texto, "[A-Z\u00C0-\u00FF]")
      if ($letras.Count -eq 0) { $pos = -1 } else { $pos = $letras[[math]::Floor($letras.Count / 2)].Index }
    }
    if ($pos -ge 0 -and $pos -lt $texto.Length) {
      $texto = $texto.Substring(0, $pos) + "{\c$($script:acentoAss)}" + $texto.Substring($pos, 1) + "{\c&H00FFFFFF&}" + $texto.Substring($pos + 1)
    }
    # un pelo de extension para que no parpadee
    $eventos += ("Dialogue: 0,{0},{1},Impacto,,0,0,0,,{2}" -f (Tiempo-Ass ($ini + $offsetSeg)), (Tiempo-Ass ($fin + $offsetSeg)), $texto)
  }
  $cab = @"
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 2
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Impacto,Impact,104,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,1,1,0,0,100,100,1,0,1,9,0,2,50,50,560,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"@
  $contenido = $cab + "`r`n" + ($eventos -join "`r`n") + "`r`n"
  [IO.File]::WriteAllText((Join-Path $PWD $assPath), $contenido, (New-Object System.Text.UTF8Encoding($false)))
  return $eventos.Count
}

# ---------- gancho: texto grande en pantalla los primeros 1,5s ----------
function Gancho2Ass([string]$texto, [string]$assPath, [double]$dur) {
  $t = $texto.Trim().ToUpper()
  $t = $t -replace "\\n", "\N"          # permite cortes de linea desde el JSON
  $t = $t -replace "`r?`n", "\N"
  # tamano automatico: si una linea es muy larga se achica para no desbordar el ancho
  $maxLen = 0
  foreach ($ln in ($t -split "\\N")) { if ($ln.Length -gt $maxLen) { $maxLen = $ln.Length } }
  $size = 116
  if ($maxLen -gt 0) {
    $anchoEstimado = $maxLen * 0.58 * $size
    if ($anchoEstimado -gt 980) { $size = [math]::Floor(980 / ($maxLen * 0.58)) }
  }
  $t = "{\fad(90,140)}$t"
  $cab = @"
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Gancho,Impact,$size,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,1,0,0,100,100,1,0,1,12,5,8,30,30,520,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"@
  $evento = ("Dialogue: 0,{0},{1},Gancho,,0,0,0,,{2}" -f (Tiempo-Ass 0.0), (Tiempo-Ass $dur), $t)
  [IO.File]::WriteAllText((Join-Path $PWD $assPath), ($cab + "`r`n" + $evento + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  return 1
}

# ---------- cta final: like / comenta / suscribete ----------
function Cta2Ass([string]$texto, [string]$assPath, [double]$dur, [double]$total) {
  $t = $texto.Trim().ToUpper()
  $t = $t -replace "\\n", "\N"
  $t = $t -replace "`r?`n", "\N"
  # la ultima linea (SUSCRIBETE) en cian de la marca
  $lineas = $t -split "\\N"
  if ($lineas.Count -ge 2) {
    $lineas[$lineas.Count - 1] = "{\c&H00FFC800&}" + $lineas[$lineas.Count - 1] + "{\c&H00FFFFFF&}"
    $t = $lineas -join "\N"
  }
  $maxLen = 0
  foreach ($ln in ($t -split "\\N")) { if ($ln.Length -gt $maxLen) { $maxLen = $ln.Length } }
  $size = 120
  if ($maxLen -gt 0) {
    $ancho = $maxLen * 0.58 * $size
    if ($ancho -gt 900) { $size = [math]::Floor(900 / ($maxLen * 0.58)) }
  }
  $inicio = [math]::Max(0, $total - $dur)
  $t = "{\fad(150,120)}$t"
  $cab = @"
[Script Info]
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Cta,Impact,$size,&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,1,1,0,0,100,100,1,0,1,9,4,8,40,40,300,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"@
  $evento = ("Dialogue: 0,{0},{1},Cta,,0,0,0,,{2}" -f (Tiempo-Ass $inicio), (Tiempo-Ass $total), $t)
  [IO.File]::WriteAllText((Join-Path $PWD $assPath), ($cab + "`r`n" + $evento + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
  return 1
}

# ---------- visual ----------
$inputArgs = @()
$filters = @()
$shotLabels = @()
$idx = 0

function AnadirPlano($plano, [double]$durEfectiva) {
  $script:idx++
  $i = $script:idx - 1
  $label = "s$i"
  $modo = if ($plano.modo) { $plano.modo } else { "fill" }
  $zoom = if ($plano.zoom) { $plano.zoom } else { "in" }
  $grade = if ($plano.grade) { $plano.grade } else { "ninguno" }

  $zExpr = switch ($zoom) {
    "in"       { "min(1+0.0006*on,1.16)" }
    "out"      { "max(1.14-0.00055*on,1.0)" }
    "in2"      { "min(1+0.0008*on,1.12)" }
    "detalle"  { "min(1.35+0.0006*on,1.50)" }
    "detalle2" { "max(1.48-0.0006*on,1.30)" }
    default { $null }
  }
  $zp = if ($zExpr) { ",zoompan=z='$zExpr':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1080x1920:fps=30" } else { "" }

  # Antitemblor: zoompan redondea x/y a pixeles enteros y el paneo "tiembla".
  # Procesando la foto a 2x y entregando 1080x1920, cada paso es medio pixel.
  $ss = if ($null -ne $cfg.zoomSuave) { [double]$cfg.zoomSuave } else { 3.0 }
  if (-not $zExpr -or $plano.tipo -ne "foto") { $ss = 1.0 }
  if ($ss -lt 1) { $ss = 1.0 }
  $wSS = [int](1080 * $ss)
  $hSS = [int](1920 * $ss)
  $fgSS = [int](1040 * $ss)

  if ($plano.tipo -eq "foto") {
    $script:inputArgs += @("-loop","1","-framerate","30","-t",(F $durEfectiva),"-i",$plano.archivo)
    if ($modo -eq "blurfill") {
      $script:filters += "[$i`:v]scale=${wSS}:${hSS}:force_original_aspect_ratio=increase,crop=${wSS}:${hSS},gblur=sigma=30,eq=brightness=-0.20:saturation=0.85[bg$i]"
      $script:filters += "[$i`:v]scale=${fgSS}:-2,eq=brightness=0.02:contrast=1.06:saturation=1.10[fg$i]"
      $script:filters += "[bg$i][fg$i]overlay=(W-w)/2:(H-h)/2$zp,setsar=1[$label]"
    } else {
      $script:filters += "[$i`:v]scale=${wSS}:${hSS}:force_original_aspect_ratio=increase,crop=${wSS}:${hSS}$zp,eq=contrast=1.06:saturation=1.05,setsar=1[$label]"
    }
  } else {
    $desde = if ($null -ne $plano.desde) { [double]$plano.desde } else { 0 }
    $script:inputArgs += @("-ss",(F $desde),"-t",(F $durEfectiva),"-i",$plano.archivo)
    $g = switch ($grade) {
      "noche" { "eq=brightness=0.13:gamma=1.45:contrast=1.12:saturation=1.12,hqdn3d=3:2:4:3" }
      "dia"   { "eq=contrast=1.08:saturation=1.06" }
      default { "null" }
    }
    $zv = ""
    if ($plano.zoom) {
      $zx = switch ($plano.zoom) {
        "out"     { "max(1.12-0.0005*on,1.0)" }
        "detalle" { "min(1.38+0.0006*on,1.55)" }
        "detalle2"{ "max(1.50-0.0006*on,1.32)" }
        default   { "min(1+0.0005*on,1.12)" }
      }
      $zv = ",zoompan=z='$zx':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=1:s=1080x1920:fps=30"
    }
    if ($modo -eq "blurfill") {
      $script:filters += "[$i`:v]split=2[vbg$i][vfg$i]"
      $script:filters += "[vbg$i]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=30,eq=brightness=-0.25:saturation=0.85[vbgf$i]"
      $script:filters += "[vfg$i]scale=1080:-2[vfgf$i]"
      $script:filters += "[vbgf$i][vfgf$i]overlay=(W-w)/2:(H-h)/2,fps=30$zv,$g,setsar=1[$label]"
    } else {
      $script:filters += "[$i`:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,fps=30$zv,$g,setsar=1[$label]"
    }
  }
  $script:shotLabels += "[$label]"
}

function VerificarMotor([string]$archivo, [double]$desde, [double]$dur, [string]$etiqueta) {
  # Corta el tramo exacto que se va a usar y lo audita con detectar-audio.py
  if (-not (Test-Path "scripts/detectar-audio.py")) { return }
  $tmp = "logs/_verif-motor.mp3"
  & $ff -hide_banner -loglevel error -y -ss $desde -t $dur -i $archivo -vn -c:a libmp3lame -b:a 128k $tmp
  if (-not (Test-Path $tmp)) { return }
  # Analisis POR VENTANAS de 1.5s: una cancion de fondo en 1 segundo se detecta
  # aunque el promedio del tramo entero de "motor".
  $ventana = 1.5
  $t = 0.0
  $malas = 0
  $sordas = 0
  $total = 0
  $detalle = @()
  while ($t -lt ($dur - 0.4)) {
    $w = [math]::Min($ventana, $dur - $t)
    if ($w -lt 0.8) { break }
    & $ff -hide_banner -loglevel error -y -ss ($desde + $t) -t $w -i $archivo -vn -c:a libmp3lame -b:a 128k $tmp
    if (Test-Path $tmp) {
      $wv = (& python scripts/detectar-audio.py $tmp 2>&1 | Select-Object -First 1) -replace "VEREDICTO: ",""
      $total++
      if ("$wv" -match "MUSICA") { $malas++; $detalle += ("{0:N1}s" -f $t) }
      if ("$wv" -match "sordo") { $sordas++ }
    }
    $t += $ventana
  }
  if ($total -eq 0) { return }
  $pct = [math]::Round(100.0 * $malas / $total, 0)
  if ($sordas -gt 0) {
    Write-Output ("  AVISO audio ${etiqueta}: MOTOR SORDO (casi toda la energia bajo 1,5 kHz) -> el auto no se reconoce")
  }
  if ($malas -gt 0) {
    $lista = ($detalle -join ", ")
    if ($pct -ge 25) {
      throw ("MOTOR CON MUSICA en $etiqueta ($archivo @ ${desde}s): $malas de $total ventanas ($pct%) -> $lista")
    }
    Write-Output ("  AVISO audio ${etiqueta}: musica en $malas de $total ventanas ($pct%) -> $lista")
  } else {
    Write-Output ("  OK audio $etiqueta -> MOTOR en $total ventanas")
  }
}

function ConstruirBloque($bloque, [double]$duracion) {
  $planos = @($bloque.visual)
  if ($planos.Count -eq 0) { throw "El bloque no tiene 'visual'" }
  $fijos = 0.0
  foreach ($p in $planos) { if ($null -ne $p.dur) { $fijos += [double]$p.dur } }
  $resto = $duracion - $fijos
  if ($resto -le 0.2) { throw ("Los planos fijos ({0:N2}s) ya superan la duracion del bloque ({1:N2}s)" -f $fijos, $duracion) }
  $asignado = $false
  foreach ($p in $planos) {
    if ($null -ne $p.dur) { AnadirPlano $p ([double]$p.dur) }
    else {
      if ($asignado) { throw "Solo un plano por bloque puede tener dur=null" }
      AnadirPlano $p $resto; $asignado = $true
    }
  }
}

# ================= TIEMPOS =================
$motores = @{}
$voces = @{}
$total = 0.0

if ($tipo -eq "versus") {
  if (-not $cfg.a -or -not $cfg.b) { throw "tipo 'versus' necesita bloques a y b" }
  $voces.a = AsegurarVoz $cfg.a "a"
  $voces.b = AsegurarVoz $cfg.b "b"
  $dA = Dur $voces.a; $dB = Dur $voces.b
  $introA = if ($null -ne $cfg.timing.introA) { [double]$cfg.timing.introA } else { 1.4 }
  $leadB  = if ($null -ne $cfg.timing.leadB)  { [double]$cfg.timing.leadB }  else { 0.6 }
  $cola   = if ($null -ne $cfg.timing.cola)   { [double]$cfg.timing.cola }   else { 0.6 }
  $TA = $introA + $dA
  $TB = $leadB + $dB + $cola
  $total = $TA + $TB
} else {
  $voces.a = AsegurarVoz $cfg.a "a"
  $dA = Dur $voces.a
  $intro = if ($null -ne $cfg.intro) { [double]$cfg.intro } else { 1.2 }
  $cola  = if ($null -ne $cfg.cola)  { [double]$cfg.cola }  else { 0.6 }

  if ($cfg.motores) {
    # --- timeline manual de motores: cada uno con su segundo de entrada ---
    $vozEn = if ($null -ne $cfg.vozEn) { [double]$cfg.vozEn } else { 0 }
    $finMotores = 0.0
    foreach ($m in $cfg.motores) {
      $e = if ($m.en -eq "finVoz") { $vozEn + $dA } elseif ($null -ne $m.en) { [double]$m.en } else { 0 }
      $finMotores = [math]::Max($finMotores, $e + [double]$m.duracion)
    }
    $total = [math]::Max($vozEn + $dA, $finMotores)
    Write-Output ("timeline manual: voz en {0:N2}s, motores hasta {1:N2}s" -f $vozEn, $finMotores)
    $mot = $null
  } else {
    $mot = $cfg.a.motor
    if ($mot -and $mot.archivo) {
      # tiene motor: sigue el flujo normal (mas abajo)
    } elseif ($cfg.sinMotor) {
      # --- reel SIN motor de auto: solo voz (+ musica opcional) ---
      $vozEn = if ($null -ne $cfg.vozEn) { [double]$cfg.vozEn } else { 0.3 }
      $total = $vozEn + $dA + $cola
      Write-Output ("sin motor: voz en {0:N2}s, total {1:N2}s" -f $vozEn, $total)
      $mot = $null
    } else {
      throw "Falta a.motor.archivo (o usa 'motores', o pon 'sinMotor': true)"
    }
  }
  if ($mot) {
    $motDesde = if ($null -ne $mot.desde) { [double]$mot.desde } else { 0 }
    $motAvail = (Dur $mot.archivo) - $motDesde
    if ($null -ne $mot.duracion) { $motAvail = [math]::Min($motAvail, [double]$mot.duracion) }
    $modo = if ($cfg.a.motorEntra) { $cfg.a.motorEntra } else { "fin" }
    if ($modo -eq "inicio") {
      $total = $dA + $intro + $cola
      if ($motAvail -lt ($total - 0.25)) {
        Write-Output ("AVISO: el motor ({0:N2}s) no alcanza para 'inicio'; se cambia a 'fin'" -f $motAvail)
        $modo = "fin"
      }
    }
    if ($modo -eq "fin") {
      $maxTot = if ($null -ne $cfg.maxDuracion) { [double]$cfg.maxDuracion } else { 25.0 }
      $total = [math]::Min($maxTot, $dA + $motAvail)
      if ($total -lt 20) { Write-Output ("AVISO: el reel queda en {0:N2}s (motor corto)" -f $total) }
    }
    $cfg.a | Add-Member -NotePropertyName motorEntra -NotePropertyValue $modo -Force
  }
}

Write-Output ("TOTAL = {0:N3}s" -f $total)
if (-not $cfg.musica) { Write-Output "AVISO: el reel no tiene musica de fondo (obligatoria al publicar)" }
$limiteDur = if ($null -ne $cfg.limiteDuracion) { [double]$cfg.limiteDuracion } else { 70.0 }
if ($total -gt $limiteDur) { throw ("Reel demasiado largo ({0:N2}s > {1:N0}s): acorta el guion" -f $total, $limiteDur) }

# ================= VISUAL =================
if ($tipo -eq "versus") {
  ConstruirBloque $cfg.a $TA
  ConstruirBloque $cfg.b $TB
} else {
  ConstruirBloque $cfg.a $total
}

$concat = ($shotLabels -join "") + "concat=n=$($shotLabels.Count):v=1:a=0"

# subtitulos palabra por palabra (opcional)
$subFiltro = ""
if ($cfg.subtitulos) {
  $vozInicio = 0.0
  if ($tipo -eq "versus") { $vozInicio = $introA }
  elseif ($cfg.motores) { $vozInicio = $vozEn }
  elseif ($cfg.sinMotor) { $vozInicio = $vozEn }
  elseif ($cfg.a.motorEntra -eq "inicio") { $vozInicio = $intro }
  $srtPath = "02-voz/$($cfg.id)-a.srt"
  $assPath = "logs/$($cfg.id).ass"
  if (Test-Path $srtPath) {
    $nEv = Srt2Ass $srtPath $assPath $vozInicio
    Write-Output ("subtitulos A: $nEv lineas (offset {0:N2}s)" -f $vozInicio)
    $subFiltro = ",subtitles=$assPath"
  } else {
    Write-Output "AVISO: no hay SRT de A"
  }
  # bloque B del versus (subtitulos con su propio desfase)
  if ($tipo -eq "versus") {
    $srtB = "02-voz/$($cfg.id)-b.srt"
    $assB = "logs/$($cfg.id)-b.ass"
    $inicioB = $TA + $leadB
    if (Test-Path $srtB) {
      $nEvB = Srt2Ass $srtB $assB $inicioB
      Write-Output ("subtitulos B: $nEvB lineas (offset {0:N2}s)" -f $inicioB)
      $subFiltro += ",subtitles=$assB"
    } else {
      Write-Output "AVISO: no hay SRT de B"
    }
  }
}

# gancho de 1,5s: texto grande desde el primer frame (palanca mas fuerte de la analitica)
$ganchoFiltro = ""
if ($cfg.gancho) {
  $durG = if ($null -ne $cfg.ganchoDur) { [double]$cfg.ganchoDur } else { 1.6 }
  $assG = "logs/$($cfg.id)-gancho.ass"
  [void](Gancho2Ass $cfg.gancho $assG $durG)
  $ganchoFiltro = ",subtitles=$assG"
  Write-Output ("gancho: '{0}' ({1:N1}s)" -f $cfg.gancho, $durG)
}

# CTA final (like / comenta / suscribete) en los ultimos segundos
$ctaFiltro = ""
$ctaOn = $true
if ($null -ne $cfg.cta -and $cfg.cta -is [bool]) { $ctaOn = [bool]$cfg.cta }
if ($ctaOn) {
  $textoCta = if ($cfg.cta -is [string] -and "$($cfg.cta)".Trim()) { $cfg.cta } else { "DALE LIKE\nCOMENTA\nSUSCRÍBETE" }
  $durCta = if ($null -ne $cfg.ctaDur) { [double]$cfg.ctaDur } else { 3.2 }
  $assCta = "logs/$($cfg.id)-cta.ass"
  [void](Cta2Ass $textoCta $assCta $durCta $total)
  $ctaFiltro = ",subtitles=$assCta"
  Write-Output ("cta: like / comenta / suscribete (ultimos {0:N1}s)" -f $durCta)
}

$filters += "$concat,tpad=stop_mode=clone:stop_duration=1,trim=0:$(F $total),setpts=PTS-STARTPTS$subFiltro$ganchoFiltro$ctaFiltro,format=yuv420p[vout]"
$fc = $filters -join ";"

if ($DryRun) {
  Write-Output "--- DRY RUN ---"
  Write-Output ("planos: " + $shotLabels.Count)
  $filters | ForEach-Object { Write-Output ("  " + $_) }
  exit 0
}

# ================= VIDEO =================
$fecha = if ($cfg.fecha) { $cfg.fecha } else { Get-Date -Format "yyyy-MM-dd" }
$outDir = "06-salida/$fecha"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$vidTmp = "logs/$($cfg.id)-video.mp4"
$argList = @("-hide_banner","-loglevel","error","-y") + $inputArgs + @("-filter_complex",$fc,"-map","[vout]","-c:v","libx264","-preset","medium","-crf","18","-r","30",$vidTmp)
& $ff @argList
if ($LASTEXITCODE -ne 0) { throw "Fallo el render de video" }
Write-Output ("video: " + (Dur $vidTmp) + "s")

# ================= AUDIO =================
$af = @()
$amixLabels = @()
# nivel del motor mientras hay voz: 0.40 = 8 dB bajo su pico (antes 0.32)
$script:nivelMotor = 0.40
$script:pendBajaMotor = (1.0 - $script:nivelMotor) / 0.3
$script:pendAltaMotor = (1.0 - $script:nivelMotor) / 0.4

function VolRamp([double]$tBaja, [double]$tAlza, [double]$dur) {
  # 1.0 hasta tBaja, baja al nivel de fondo en 0.3s, sube a 1.0 desde tAlza en 0.4s
  $nivel = F $script:nivelMotor
  $pendBaja = F $script:pendBajaMotor
  $pendAlta = F $script:pendAltaMotor
  $b = F $tBaja; $b2 = F ($tBaja + 0.3); $a = F $tAlza; $a2 = F ($tAlza + 0.4)
  return ("volume='if(lt(t,$b),1,if(lt(t,$b2),1-(t-$b)*$pendBaja,if(lt(t,$a),$nivel,if(lt(t,$a2),$nivel+(t-$a)*$pendAlta,1))))':eval=frame")
}

if ($tipo -eq "versus") {
  $mA = $cfg.a.motor; $mB = $cfg.b.motor
  $dAstart = if ($null -ne $mA.desde) { [double]$mA.desde } else { 0 }
  $dBstart = if ($null -ne $mB.desde) { [double]$mB.desde } else { 0 }
  $volA = VolRamp ($introA - 0.15) 99999
  $nvB = F $script:nivelMotor
  $pbB = F $script:pendBajaMotor
  $paB = F $script:pendAltaMotor
  $volB = "volume='if(lt(t,$(F ($TA+$leadB-0.15))),1,if(lt(t,$(F ($TA+$leadB+0.15))),1-(t-$(F ($TA+$leadB-0.15)))*$pbB,if(lt(t,$(F ($total-$cola))),$nvB,if(lt(t,$(F ($total-$cola+0.4))),$nvB+(t-$(F ($total-$cola)))*$paB,1))))':eval=frame"
  $af += "[0:a]atrim=$(F $dAstart):$(F ($dAstart+$TA)),asetpts=PTS-STARTPTS,$volA[mA]"
  $af += "[1:a]adelay=$([int]($introA*1000))|$([int]($introA*1000))[vA]"
  $durBmot = if ($null -ne $mB.duracion) { [math]::Min($TB, [double]$mB.duracion) } else { $TB }
  $af += "[2:a]atrim=$(F $dBstart):$(F ($dBstart+$durBmot)),asetpts=PTS-STARTPTS,adelay=$([int]($TA*1000))|$([int]($TA*1000)),$volB[mB]"
  $af += "[3:a]adelay=$([int](($TA+$leadB)*1000))|$([int](($TA+$leadB)*1000))[vB]"
  $af += "[mA][vA][mB][vB]amix=inputs=4:duration=longest:normalize=0,atrim=0:$(F $total)[aout]"
  VerificarMotor $mA.archivo $dAstart $TA "A"
  VerificarMotor $mB.archivo $dBstart $TB "B"
  $audioInputs = @("-i",$mA.archivo,"-i",$voces.a,"-i",$mB.archivo,"-i",$voces.b)
} else {
  if ($cfg.motores) {
    # --- timeline manual: input 0 = voz, inputs 1..N = cada motor ---
    $audioInputs = @("-i", $voces.a)
    $af += "[0:a]adelay=$([int]($vozEn*1000))|$([int]($vozEn*1000))[voz]"
    $mezcla = "[voz]"
    $n = 1
    foreach ($m in $cfg.motores) {
      $desde = if ($null -ne $m.desde) { [double]$m.desde } else { 0 }
      $dur   = [double]$m.duracion
      $en    = if ($m.en -eq "finVoz") { $vozEn + $dA } elseif ($null -ne $m.en) { [double]$m.en } else { 0 }
      $vol   = if ($null -ne $m.vol) { [double]$m.vol } else { 1.0 }
      VerificarMotor $m.archivo $desde $dur ("motor {0}" -f $n)
      $audioInputs += @("-i", $m.archivo)
      $af += ("[{0}:a]atrim={1}:{2},asetpts=PTS-STARTPTS,volume={3},afade=t=in:st=0:d=0.10,adelay={4}|{4}[m{0}]" -f $n, (F $desde), (F ($desde+$dur)), (F $vol), [int]($en*1000))
      $mezcla += "[m$n]"
      $n++
    }
    $af += ($mezcla + ("amix=inputs={0}:duration=longest:normalize=0,atrim=0:{1},asetpts=PTS-STARTPTS[aout]" -f $n, (F $total)))
  } else {
    if ($mot) {
      $motDesde = if ($null -ne $mot.desde) { [double]$mot.desde } else { 0 }
      if ($cfg.a.motorEntra -eq "inicio") {
        $vol = VolRamp ($intro - 0.15) 99999
        $af += "[0:a]atrim=$(F $motDesde):$(F ($motDesde+$total)),asetpts=PTS-STARTPTS,$vol[mA]"
        $af += "[1:a]adelay=$([int]($intro*1000))|$([int]($intro*1000))[vA]"
        $af += "[mA][vA]amix=inputs=2:duration=longest:normalize=0,atrim=0:$(F $total)[aout]"
      } else {
        $usar = [math]::Min(($total - $dA), ((Dur $mot.archivo) - $motDesde))
      VerificarMotor $mot.archivo $motDesde $usar "unico"
        $af += "[0:a]atrim=$(F $motDesde):$(F ($motDesde+$usar)),asetpts=PTS-STARTPTS,adelay=$([int]($dA*1000))|$([int]($dA*1000))[mA]"
        $af += "[1:a]volume=1.0[vA]"
        $af += "[vA][mA]amix=inputs=2:duration=longest:normalize=0,atrim=0:$(F $total)[aout]"
      }
      $audioInputs = @("-i",$mot.archivo,"-i",$voces.a)
    } else {
      # --- SIN motor: solo voz (+ musica de fondo opcional) ---
      $audioInputs = @("-i", $voces.a)
      $af += "[0:a]adelay=$([int]($vozEn*1000))|$([int]($vozEn*1000))[voz]"
      $mezcla = "[voz]"
      $n = 1
      if ($cfg.musica -and $cfg.musica.archivo) {
        $volMus = if ($null -ne $cfg.musica.vol) { [double]$cfg.musica.vol } else { 0.15 }
        $audioInputs += @("-stream_loop","-1","-i",$cfg.musica.archivo)
        $af += ("[{0}:a]volume={1},atrim=0:{2},afade=t=in:st=0:d=1,afade=t=out:st={3}:d=0.4[mus]" -f $n, (F $volMus), (F $total), (F ($total-0.5)))
        $mezcla += "[mus]"
        $n++
        Write-Output ("  musica de fondo: " + (Split-Path $cfg.musica.archivo -Leaf) + " al " + ($volMus*100) + "%")
      }
      $af += ($mezcla + ("amix=inputs={0}:duration=longest:normalize=0,apad=whole_dur={1},atrim=0:{1},asetpts=PTS-STARTPTS[aout]" -f $n, (F $total)))
    }
  }
}

$mixTmp = "logs/$($cfg.id)-mix.m4a"
$argA = @("-hide_banner","-loglevel","error","-y") + $audioInputs + @("-filter_complex",($af -join ";"),"-map","[aout]","-c:a","aac","-b:a","192k","-ar","48000",$mixTmp)
& $ff @argA
if ($LASTEXITCODE -ne 0) { throw "Fallo el render de audio" }
Write-Output ("mix: " + (Dur $mixTmp) + "s")

# ================= LOUDNESS 2 PASADAS =================
$json = (& $ff -hide_banner -i $mixTmp -af "loudnorm=I=-14:TP=-1.5:LRA=11:print_format=json" -f null NUL 2>&1 | Out-String)
$m = [regex]::Match($json, '(?s)\{.*\}')
if ($m.Success) {
  $d = $m.Value | ConvertFrom-Json
  $ln = "loudnorm=I=-14:TP=-1.5:LRA=11:measured_I=$($d.input_i):measured_TP=$($d.input_tp):measured_LRA=$($d.input_lra):measured_thresh=$($d.input_thresh):offset=$($d.target_offset):linear=true,alimiter=limit=0.85:level=false"
  $mix2 = "logs/$($cfg.id)-mix2.m4a"
  & $ff -hide_banner -loglevel error -y -i $mixTmp -af $ln -c:a aac -b:a 192k -ar 48000 $mix2
  if (Test-Path $mix2) { $mixTmp = $mix2 }
  Write-Output ("loudness aplicado desde I=$($d.input_i) TP=$($d.input_tp)")
}

# ================= MUX =================
$salida = if ($cfg.salida) { $cfg.salida } else { "$($cfg.id).mp4" }
$final = Join-Path $outDir $salida
& $ff -hide_banner -loglevel error -y -i $vidTmp -i $mixTmp -c:v copy -c:a copy -shortest $final
Write-Output ("FINAL: $final  (" + (Dur $final) + "s)")
if ($cfg.meta) {
  $cfg.meta | ConvertTo-Json -Depth 5 | Set-Content -Path ([IO.Path]::Combine($outDir, "$($cfg.id).meta.json")) -Encoding UTF8
}
