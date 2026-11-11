# alinear-srt.py - Genera un SRT palabra por palabra alineando un audio con su guion
#
# Uso:
#   python scripts/alinear-srt.py <audio.mp3> <texto.txt> <salida.srt> [mapa.json] [modelo]
#
# Para que sirve:
#   - Gemini TTS (y casi cualquier TTS) no devuelve tiempos por palabra.
#   - Se transcribe el audio con faster-whisper (marca de tiempo por palabra) y se
#     alinea esa transcripcion contra el guion ORIGINAL con difflib.
#   - El SRT final muestra el texto del guion (no lo que "entendio" Whisper).
#
# mapa.json (opcional, mismo formato que tts-palabras.py):
#   { "mostrar": { "ene a ese a": "NASA", "cuatro punto ocho": "4.8" } }
#
# Requiere: pip install faster-whisper "av==12.3.0"
import difflib, io, json, os, re, sys, time, unicodedata
os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")
from faster_whisper import WhisperModel


def norm(w):
    w = unicodedata.normalize("NFD", w.lower())
    w = "".join(c for c in w if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "", w)


def fmt(seg):
    h = int(seg // 3600)
    m = int((seg % 3600) // 60)
    s = int(seg % 60)
    ms = int(round((seg - int(seg)) * 1000))
    if ms >= 1000:
        ms = 999
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


def repartir(palabras, ini, fin):
    """Reparte un tramo entre varias palabras segun su largo."""
    if not palabras:
        return []
    if fin <= ini:
        fin = ini + 0.12 * len(palabras)
    pesos = [max(len(norm(p)), 1) for p in palabras]
    total = float(sum(pesos))
    salida, t = [], ini
    for p, peso in zip(palabras, pesos):
        d = max(0.12, (fin - ini) * peso / total)
        salida.append((t, min(t + d, fin)))
        t += d
    return salida


def alinear(rec, guion):
    """rec: [(ini, fin, texto)] | guion: [palabra]. Devuelve [(ini, fin, palabra)]."""
    a = [norm(r[2]) for r in rec]
    b = [norm(g) for g in guion]
    tiempos = [None] * len(guion)
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(j2 - j1):
                tiempos[j1 + k] = (rec[i1 + k][0], rec[i1 + k][1])
        elif tag == "replace":
            ini = rec[i1][0] if i1 < len(rec) else (rec[i1 - 1][1] if i1 > 0 else 0.0)
            fin = rec[i2 - 1][1] if i2 > 0 else ini + 0.4
            for k, (s, e) in enumerate(repartir(guion[j1:j2], ini, fin)):
                tiempos[j1 + k] = (s, e)
        elif tag == "insert":
            ini = rec[i1 - 1][1] if i1 > 0 else 0.0
            fin = rec[i1][0] if i1 < len(rec) else ini + 0.3 * (j2 - j1)
            for k, (s, e) in enumerate(repartir(guion[j1:j2], ini, fin)):
                tiempos[j1 + k] = (s, e)
        # delete: palabras que Whisper escucho y no estan en el guion -> se ignoran

    # huecos: interpolar entre vecinos conocidos
    for i, t in enumerate(tiempos):
        if t is not None:
            continue
        prev = next((tiempos[k][1] for k in range(i - 1, -1, -1) if tiempos[k]), 0.0)
        nxt = next((tiempos[k][0] for k in range(i + 1, len(tiempos)) if tiempos[k]), prev + 0.3)
        d = max(0.12, (nxt - prev) / 2.0)
        tiempos[i] = (prev, min(prev + d, nxt))

    # monotonos y sin solapes
    out, ultimo = [], 0.0
    for (g, (s, e)) in zip(guion, tiempos):
        s = max(s, ultimo)
        e = max(e, s + 0.1)
        out.append((s, e, g))
        ultimo = e
    return out


def fusionar(items, reglas):
    """Une palabras que deben mostrarse juntas (NASA, 4.8, etc.)."""
    reglas = sorted(reglas, key=lambda r: -len(r[0]))
    salida, i = [], 0
    while i < len(items):
        ini, fin, txt = items[i]
        encontrado = False
        for clave, mostrar in reglas:
            acum, j, ultimo = "", i, None
            while j < len(items) and len(acum) < len(clave):
                acum += norm(items[j][2])
                ultimo = items[j]
                if not clave.startswith(acum):
                    break
                j += 1
            if acum == clave and ultimo is not None:
                salida.append((ini, max(fin, ultimo[1]), mostrar))
                i = j
                encontrado = True
                break
        if not encontrado:
            salida.append(items[i])
            i += 1
    return salida


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__ or "Uso: alinear-srt.py <audio> <texto.txt> <salida.srt> [mapa.json] [modelo]")
    audio, txt_path, srt_path = sys.argv[1:4]
    mapa = {}
    modelo = "base"
    if len(sys.argv) > 4 and sys.argv[4] and sys.argv[4] != "-":
        with io.open(sys.argv[4], encoding="utf-8") as f:
            mapa = json.load(f)
    if len(sys.argv) > 5 and sys.argv[5]:
        modelo = sys.argv[5]

    with io.open(txt_path, encoding="utf-8") as f:
        texto = f.read().strip()
    guion = texto.split()
    if not guion:
        sys.exit("El guion esta vacio")

    t = time.time()
    m = WhisperModel(modelo, device="cpu", compute_type="int8")
    segs, info = m.transcribe(audio, language="es", word_timestamps=True, beam_size=1,
                              vad_filter=True, condition_on_previous_text=False)
    rec = []
    for s in segs:
        for w in s.words or []:
            rec.append((w.start, w.end, w.word.strip()))
    if not rec:
        sys.exit("Whisper no detecto voz en el audio")

    items = alinear(rec, guion)
    mostrar = {}
    for k, v in (mapa.get("mostrar") or {}).items():
        clave = norm(k)
        if clave:
            mostrar[clave] = v
    if mostrar:
        items = fusionar(items, list(mostrar.items()))

    lineas = []
    for idx, (ini, _fin, txt) in enumerate(items):
        if idx + 1 < len(items):
            fin = max(ini + 0.15, items[idx + 1][0] - 0.02)
        else:
            fin = max(ini + 0.25, _fin)
        lineas.append("%d\n%s --> %s\n%s\n" % (idx + 1, fmt(ini), fmt(fin), txt))

    with io.open(srt_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))

    ratio = difflib.SequenceMatcher(None, [norm(r[2]) for r in rec],
                                    [norm(g) for g in guion], autojunk=False).ratio()
    print("alineado: %d palabras | %d lineas | coincidencia %.0f%% | %.1fs"
          % (len(guion), len(items), ratio * 100, time.time() - t))
    if ratio < 0.75:
        print("AVISO: coincidencia baja. Revisa el SRT antes de renderizar.")


if __name__ == "__main__":
    main()
