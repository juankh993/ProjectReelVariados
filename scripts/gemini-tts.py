# gemini-tts.py - Genera voz con Gemini TTS (Google AI Studio)
#
# Uso:
#   python scripts/gemini-tts.py <texto.txt> <voz> <salida.mp3> [modelo]
#
# Ejemplo:
#   python scripts/gemini-tts.py logs/guion.txt Iapetus 02-voz/reel-a.mp3
#
# - La llave se toma de .google-ai.key (o de GEMINI_API_KEY).
# - Salida de la API: PCM 16 bits, 24 kHz, mono -> se convierte a MP3 con ffmpeg.
# - OJO: Gemini TTS NO devuelve tiempos por palabra. Para subtitulos hay que
#   alinear despues con scripts/alinear-srt.py (faster-whisper).
import base64, io, os, subprocess, sys, tempfile, time, urllib.error, urllib.request
import json

MODELO_DEF = "gemini-2.5-flash-preview-tts"


def leer_key():
    env = os.environ.get("GEMINI_API_KEY")
    if env:
        return env.strip()
    for ruta in (".google-ai.key", os.path.join(os.path.dirname(__file__), "..", ".google-ai.key")):
        if os.path.exists(ruta):
            with io.open(ruta, encoding="utf-8") as f:
                return f.read().strip()
    sys.exit("Falta .google-ai.key o GEMINI_API_KEY")


def registrar(estado, voz, seg):
    """Deja un registro para controlar la cuota diaria de Gemini."""
    try:
        if not os.path.isdir("logs"):
            os.makedirs("logs")
        with io.open(os.path.join("logs", "tts-cuota.txt"), "a", encoding="utf-8") as f:
            f.write("%s %-6s %-10s %5.1fs\n" % (time.strftime("%Y-%m-%d %H:%M"), estado, voz, seg))
    except OSError:
        pass


def sintetizar(texto, voz, modelo):
    key = leer_key()
    cuerpo = {
        "contents": [{"parts": [{"text": texto}]}],
        "generationConfig": {
            "responseModalities": ["AUDIO"],
            "speechConfig": {"voiceConfig": {"prebuiltVoiceConfig": {"voiceName": voz}}},
        },
    }
    url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % modelo
    req = urllib.request.Request(
        url,
        data=json.dumps(cuerpo).encode("utf-8"),
        headers={"Content-Type": "application/json", "x-goog-api-key": key},
    )
    for intento in (1, 2):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            detalle = e.read().decode("utf-8", "replace")
            if e.code == 429:
                # Limite por minuto: un reintento. Limite diario: fallback inmediato.
                if intento == 1 and "per day" not in detalle.lower() and "daily" not in detalle.lower():
                    print("Limite por minuto; reintento en 20s...", file=sys.stderr)
                    time.sleep(20)
                    continue
                print("Cuota de Gemini TTS agotada (429).", file=sys.stderr)
                print(detalle[:400], file=sys.stderr)
                registrar("CUOTA", voz, 0)
                sys.exit(2)
            print("Error %s de Gemini TTS:" % e.code, file=sys.stderr)
            print(detalle[:600], file=sys.stderr)
            registrar("ERROR", voz, 0)
            sys.exit(3)
        except Exception as e:
            print("Fallo de red con Gemini TTS: %s" % e, file=sys.stderr)
            registrar("ERROR", voz, 0)
            sys.exit(3)


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__ or "Uso: gemini-tts.py <texto.txt> <voz> <salida.mp3> [modelo]")
    txt_path, voz, salida = sys.argv[1:4]
    modelo = sys.argv[4] if len(sys.argv) > 4 else MODELO_DEF

    with io.open(txt_path, encoding="utf-8") as f:
        texto = f.read().strip()
    if not texto:
        sys.exit("El texto esta vacio")

    t = time.time()
    resp = sintetizar(texto, voz, modelo)
    partes = resp.get("candidates", [{}])[0].get("content", {}).get("parts", [])
    if not partes or "inlineData" not in partes[0]:
        print("La API no devolvio audio: " + json.dumps(resp)[:400], file=sys.stderr)
        sys.exit(4)
    inline = partes[0]["inlineData"]
    pcm = base64.b64decode(inline["data"])
    mime = inline.get("mimeType", "")

    tmp = os.path.join(tempfile.gettempdir(), "gemini-tts-%d.pcm" % int(t))
    with open(tmp, "wb") as f:
        f.write(pcm)
    try:
        # audio/L16;codec=pcm;rate=24000  -> PCM crudo s16le mono
        cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
               "-f", "s16le", "-ar", "24000", "-ac", "1", "-i", tmp,
               "-c:a", "libmp3lame", "-b:a", "192k", "-ar", "48000", salida]
        subprocess.run(cmd, check=True)
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass

    dur = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", salida],
        capture_output=True, text=True,
    ).stdout.strip()
    registrar("OK", voz, float(dur or 0))
    print("OK %s | voz=%s | modelo=%s | %.1fs de audio | API %.1fs"
          % (salida, voz, modelo, float(dur or 0), time.time() - t))


if __name__ == "__main__":
    main()
