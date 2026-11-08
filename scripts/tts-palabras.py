# tts-palabras.py - Genera voz con edge-tts y un SRT con UNA PALABRA por linea
# Uso: python scripts/tts-palabras.py <texto.txt> <voz> <salida.mp3> <salida.srt> [mapa.json]
#
# mapa.json (opcional):
#   { "decir": "texto que se sintetiza (puede diferir del de pantalla)",
#     "mostrar": { "dos punto cinco dieciseis": "2.5-16" } }
# Sirve para que el TTS diga una cosa y el subtitulo muestre otra (siglas, decimales,
# fechas). Las palabras habladas que coinciden con una clave se fusionan en una sola
# linea con el texto de pantalla y el tiempo que va de la primera a la ultima.
import asyncio, sys, io, json, re, unicodedata
import edge_tts

TICKS = 10_000_000.0  # 100 ns por tick


def fmt(seg):
    h = int(seg // 3600)
    m = int((seg % 3600) // 60)
    s = int(seg % 60)
    ms = int(round((seg - int(seg)) * 1000))
    if ms >= 1000:
        ms = 999
    return "%02d:%02d:%02d,%03d" % (h, m, s, ms)


def norm(w):
    w = unicodedata.normalize("NFD", w.lower())
    w = "".join(c for c in w if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "", w)


async def main():
    txt_path, voice, mp3_path, srt_path = sys.argv[1:5]

    mapa = {}
    if len(sys.argv) > 5 and sys.argv[5] and sys.argv[5] != "-":
        with io.open(sys.argv[5], encoding="utf-8") as f:
            mapa = json.load(f)

    with io.open(txt_path, encoding="utf-8") as f:
        texto = f.read()

    decir = mapa.get("decir") or texto
    reglas = []
    for k, v in (mapa.get("mostrar") or {}).items():
        clave = norm(k)
        if clave:
            reglas.append((clave, v))
    reglas.sort(key=lambda r: -len(r[0]))  # primero las frases mas largas

    com = edge_tts.Communicate(decir, voice, boundary="WordBoundary")
    palabras = []
    with open(mp3_path, "wb") as out:
        async for chunk in com.stream():
            if chunk["type"] == "audio":
                out.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                palabras.append((chunk["offset"] / TICKS, chunk["duration"] / TICKS, chunk["text"]))

    if not palabras:
        sys.exit("sin WordBoundary")

    # fusion de palabras segun las reglas de "mostrar"
    # se compara por concatenacion normalizada: asi "190 E" (un token) casa con
    # la clave "190 e" y "3 E" + "30" casa con "3 e 30".
    items = []  # (ini, fin, texto)
    i = 0
    while i < len(palabras):
        ini, dur, txt = palabras[i]
        encontrado = False
        for clave, mostrar in reglas:
            acumulado = ""
            ultimo = None
            j = i
            while j < len(palabras) and len(acumulado) < len(clave):
                acumulado += norm(palabras[j][2])
                ultimo = palabras[j]
                if not clave.startswith(acumulado):
                    break
                j += 1
            if acumulado == clave and ultimo is not None:
                fin = max(ini + 0.2, ultimo[0] + max(ultimo[1], 0.3))
                items.append((ini, fin, mostrar))
                i = j
                encontrado = True
                break
        if not encontrado:
            items.append((ini, ini + max(dur, 0.2), txt))
            i += 1

    # se mantiene cada linea hasta la siguiente (sin huecos ni solapes)
    lineas = []
    for idx, (ini, fin_propia, txt) in enumerate(items):
        if idx + 1 < len(items):
            fin = max(ini + 0.15, items[idx + 1][0] - 0.02)
        else:
            fin = fin_propia
        lineas.append("%d\n%s --> %s\n%s\n" % (idx + 1, fmt(ini), fmt(fin), txt))

    with io.open(srt_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lineas))

    print("palabras: %d | lineas: %d | duracion: %.2fs" % (len(palabras), len(items), palabras[-1][0] + palabras[-1][1]))


asyncio.run(main())
