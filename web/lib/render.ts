import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { ROOT } from "./config";
import { elegirMaterial, escanear, musicaDisponible, type Material } from "./material";

/** Raíz del pipeline (un nivel arriba de web/). */
export const PIPELINE = path.resolve(ROOT, "..");

export type Escena = {
  n?: number;
  descripcion?: string;
  busqueda?: string;
  dur?: number;
  movimiento?: string;
};

export type Plan = {
  titulo?: string;
  gancho?: string;
  vozTexto?: string;
  duracion?: number;
  escenas?: Escena[];
  musica?: string;
  cierre?: string;
};

export type EstadoTrabajo = {
  id: string;
  estado: "encolado" | "renderizando" | "listo" | "error";
  progreso: number;
  mensaje: string;
  video?: string;
  config?: string;
  log: string[];
  iniciado: number;
  terminado?: number;
};

const trabajos = new Map<string, EstadoTrabajo>();

export function obtenerTrabajo(id: string): EstadoTrabajo | undefined {
  return trabajos.get(id);
}

function slug(texto: string): string {
  return texto
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40) || "reel";
}

function hoy(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/** Arma la config que entiende scripts/reel.ps1 a partir del plan del chat. */
export function construirConfig(
  plan: Plan,
  material: Material[],
  factor = 1,
): Record<string, unknown> {
  const escenas = (plan.escenas ?? []).filter(Boolean);
  if (escenas.length === 0) throw new Error("El plan no tiene escenas.");

  const usados = new Set<string>();
  const visual: Array<Record<string, unknown>> = [];

  for (const e of escenas) {
    const consulta = `${e.busqueda ?? ""} ${e.descripcion ?? ""}`.trim();
    const elegido = elegirMaterial(material, consulta, usados);
    if (!elegido) continue;
    usados.add(elegido.ruta);

    const dur = Math.min(8, Math.max(2.5, Number(e.dur) || 5));

    visual.push({
      tipo: elegido.tipo,
      archivo: elegido.ruta,
      ...(elegido.tipo === "video" ? { desde: 0 } : {}),
      dur,
      zoom: e.movimiento === "out" ? "out" : e.movimiento === "none" ? "" : "in",
      modo: elegido.tipo === "foto" ? "blurfill" : "fill",
      _busqueda: e.busqueda ?? "",
    });
  }

  if (visual.length === 0) throw new Error("No hay material visual disponible en 03-visual/.");

  // La última escena absorbe la diferencia de tiempo.
  visual[visual.length - 1].dur = null;

  const cierre = (plan.cierre ?? "").trim();
  const voz = (plan.vozTexto ?? "").trim();
  const vozTexto = cierre && !voz.includes(cierre) ? `${voz} ${cierre}` : voz;
  if (!vozTexto) throw new Error("El plan no tiene texto de voz.");

  // Los planos fijos NO pueden sumar más que la voz. Estimamos la duración de la voz
  // (edge-tts en español ≈ 13 caracteres por segundo) y dejamos aire para el último plano.
  const estimadoVoz = Math.max(6, vozTexto.length / 13);
  const objetivoFijos = Math.max(2.5, estimadoVoz * 0.62 * factor);
  const fijos = visual.slice(0, -1);

  if (fijos.length > 0) {
    const suma = fijos.reduce((acc, v) => acc + Number(v.dur ?? 0), 0);
    if (suma > objetivoFijos) {
      const escala = objetivoFijos / suma;
      for (const v of fijos) {
        v.dur = Math.max(2, Number(((Number(v.dur) || 3) * escala).toFixed(2)));
      }
    }
  }

  const musica = musicaDisponible(PIPELINE);
  const pista = musica.length ? musica[Math.floor(Math.random() * musica.length)] : null;

  return {
    tipo: "footage",
    fecha: hoy(),
    salida: "reel.mp4",
    sinMotor: true,
    subtitulos: true,
    gancho: (plan.gancho ?? "").replace(/\|/g, "\n"),
    ganchoDur: 1.8,
    vozEn: 0.3,
    cola: 0.8,
    limiteDuracion: Math.max(60, Math.round(Number(plan.duracion) || 45) + 15),
    a: { vozTexto, visual },
    ...(pista ? { musica: { archivo: pista, vol: 0.14 } } : {}),
  };
}

function ejecutar(
  comando: string,
  args: string[],
  cwd: string,
  onLinea: (linea: string) => void,
): Promise<number> {
  return new Promise((resolve) => {
    const hijo = spawn(comando, args, { cwd, windowsHide: true });

    const leer = (buffer: Buffer) => {
      for (const linea of buffer.toString("utf8").split(/\r?\n/)) {
        const limpia = linea.trim();
        if (limpia) onLinea(limpia);
      }
    };

    hijo.stdout?.on("data", leer);
    hijo.stderr?.on("data", leer);
    hijo.on("error", (e) => {
      onLinea(`ERROR al lanzar el proceso: ${e.message}`);
      resolve(-1);
    });
    hijo.on("close", (codigo) => resolve(codigo ?? -1));
  });
}

/** Lanza el render en segundo plano y devuelve el id del trabajo. */
export function iniciarRender(plan: Plan): EstadoTrabajo {
  const material = escanear(PIPELINE);

  const fecha = hoy();
  const id = `${fecha}-${slug(String(plan.titulo ?? "reel"))}-${Math.random().toString(36).slice(2, 6)}`;

  const trabajo: EstadoTrabajo = {
    id,
    estado: "encolado",
    progreso: 0,
    mensaje: "Encolado",
    log: [],
    iniciado: Date.now(),
  };
  trabajos.set(id, trabajo);

  const anotar = (linea: string) => {
    trabajo.log.push(linea);
    if (trabajo.log.length > 400) trabajo.log.shift();
    if (linea.startsWith("TOTAL") || linea.includes("FINAL:")) trabajo.progreso = 70;
    if (linea.includes("OK audio")) trabajo.progreso = 55;
    if (linea.toLowerCase().includes("subtitulo")) trabajo.progreso = 65;
  };

  void (async () => {
    try {
      trabajo.estado = "renderizando";
      trabajo.progreso = 8;
      trabajo.mensaje = "Eligiendo material y preparando el guion…";

      const dirGuiones = path.join(PIPELINE, "01-guiones", fecha);
      fs.mkdirSync(dirGuiones, { recursive: true });
      const configRel = `01-guiones/${fecha}/${id}.json`;
      const configAbs = path.join(PIPELINE, configRel);

      let factor = 1;
      let codigo = -1;
      let salidaRel = "";

      // Hasta 3 intentos: si los planos fijos no entran en la voz, se acortan y se repite.
      for (let intento = 0; intento < 3; intento++) {
        const cfg = construirConfig(plan, material, factor);
        cfg.id = id;
        cfg.fecha = fecha;
        cfg.salida = `${id}.mp4`;
        salidaRel = `06-salida/${fecha}/${String(cfg.salida)}`;

        fs.writeFileSync(configAbs, JSON.stringify(cfg, null, 2), "utf8");
        trabajo.config = configRel;
        trabajo.mensaje =
          intento === 0 ? "Generando voz y montando el video…" : `Reintento ${intento}…`;

        codigo = await ejecutar(
          "powershell.exe",
          [
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            path.join(PIPELINE, "scripts", "reel.ps1"),
            "-Config",
            configRel,
          ],
          PIPELINE,
          anotar,
        );

        if (codigo === 0) break;

        const planosLargos = trabajo.log.some((l) => l.includes("planos fijos"));
        if (!planosLargos) break;

        factor *= 0.55;
        anotar(`→ Los planos no entraban en la voz: reintento con planos más cortos.`);
        trabajo.progreso = 8;
      }

      if (codigo !== 0) {
        trabajo.estado = "error";
        trabajo.mensaje = `El render falló (código ${codigo}). Revisá el log.`;
        trabajo.terminado = Date.now();
        return;
      }

      trabajo.progreso = 80;
      trabajo.mensaje = "Normalizando volumen…";

      const salidaAbs = path.join(PIPELINE, salidaRel);

      if (fs.existsSync(salidaAbs)) {
        await ejecutar(
          "powershell.exe",
          [
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            path.join(PIPELINE, "scripts", "fix-loudness.ps1"),
            "-Entrada",
            salidaRel,
          ],
          PIPELINE,
          anotar,
        );
      }

      if (!fs.existsSync(salidaAbs)) {
        trabajo.estado = "error";
        trabajo.mensaje = "El render terminó pero no se encontró el MP4.";
        trabajo.terminado = Date.now();
        return;
      }

      trabajo.estado = "listo";
      trabajo.progreso = 100;
      trabajo.mensaje = "Video listo";
      trabajo.video = salidaRel;
      trabajo.terminado = Date.now();
    } catch (error) {
      trabajo.estado = "error";
      trabajo.mensaje = error instanceof Error ? error.message : "Error inesperado";
      trabajo.terminado = Date.now();
    }
  })();

  return trabajo;
}

export function resolverVideo(rel: string): string | null {
  const abs = path.resolve(PIPELINE, rel);
  if (!abs.startsWith(PIPELINE)) return null;
  if (!fs.existsSync(abs)) return null;
  return abs;
}
