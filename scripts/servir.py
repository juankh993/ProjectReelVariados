# servir.py - Servidor HTTP con soporte de Range (streaming de video) para revision local
#
# Uso:
#   python scripts/servir.py [carpeta] [puerto]
#
# Diferencias con `python -m http.server`:
#   - Soporta peticiones Range (206 Partial Content) -> el navegador puede
#     reproducir y buscar sin descargar el archivo entero.
#   - Envia Content-Length y Accept-Ranges, y reintenta con timeouts largos.
import http.server
import os
import socket
import sys

CARPETA = sys.argv[1] if len(sys.argv) > 1 else "06-salida"
PUERTO = int(sys.argv[2]) if len(sys.argv) > 2 else 8840


class RangeHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=CARPETA, **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def do_GET(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            return super().do_GET()
        if not os.path.isfile(path):
            self.send_error(404, "No existe")
            return

        size = os.path.getsize(path)
        rng = self.headers.get("Range")
        ctype = self.guess_type(path)

        if rng and rng.startswith("bytes="):
            try:
                parte = rng.replace("bytes=", "").split("-")
                inicio = int(parte[0]) if parte[0] else 0
                fin = int(parte[1]) if len(parte) > 1 and parte[1] else size - 1
            except ValueError:
                inicio, fin = 0, size - 1
            if inicio >= size:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % size)
                self.end_headers()
                return
            fin = min(fin, size - 1)
            largo = fin - inicio + 1
            self.send_response(206)
            self.send_header("Content-Type", ctype)
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Range", "bytes %d-%d/%d" % (inicio, fin, size))
            self.send_header("Content-Length", str(largo))
            self.end_headers()
            with open(path, "rb") as f:
                f.seek(inicio)
                restante = largo
                while restante > 0:
                    bloque = f.read(min(256 * 1024, restante))
                    if not bloque:
                        break
                    self.wfile.write(bloque)
                    restante -= len(bloque)
            return

        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        with open(path, "rb") as f:
            while True:
                bloque = f.read(256 * 1024)
                if not bloque:
                    break
                self.wfile.write(bloque)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    socket.setdefaulttimeout(180)
    print("Sirviendo %s en http://0.0.0.0:%d/ (Range activado)" % (os.path.abspath(CARPETA), PUERTO))
    Server(("0.0.0.0", PUERTO), RangeHandler).serve_forever()
