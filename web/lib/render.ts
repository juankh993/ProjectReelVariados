import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { ROOT } from "./config";
import {
  elegirGenerico,
  elegirMaterial,
  escanear,
  musicaDisponible,
  palabrasClave,
  type Material,
} from "./material";

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
  estimadoSegundos: number;
  terminado?: number;
};

const trabajos = new Map<string, EstadoTrabajo>();

export function obtenerTrabajo(id: string): EstadoTrabajo | undefined {
  return trabajos.get(id);
}

function slug(texto: string): string {
  return (
    texto
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 40) || "reel"
  );
}

function hoy(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
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

/** Descarga fotos nuevas para una búsqueda concreta (Unsplash → Pixabay). */
async function descargarFotos(consulta: string, anotar: (l: string) => void): Promise<boolean> {
  const palabras = palabrasClave(consulta);
  if (palabras.length === 0) return false;

  const query = palabras.slice(0, 4).join(" ");
  const salida = "03-visual/panel";

  const intentos: Array<[string, string[]]> = [
    [
      "buscar-unsplash.ps1",
      ["-Query", query, "-Cantidad", "2", "-Orientacion", "vertical", "-Salida", salida, "-TrackDownload"],
    ],
    [
      "buscar-fotos.ps1",
      ["-Query", query, "-Cantidad", "2", "-Orientacion", "vertical", "-Salida", salida],
    ],
  ];

  for (const [script, args] of intentos) {
    const ruta = path.join(PIPELINE, "scripts", script);
    if (!fs.existsSync(ruta)) continue;

    anotar(`  buscando material nuevo: "${query}" con ${script}`);
    const codigo = await ejecutar("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ruta, ...args], PIPELINE, anotar);
    if (codigo === 0) return true;
  }
  return false;
}

type Resuelta = { material: Material; dur: number; movimiento: string };

/**
 * Resuelve el material de cada escena:
 *  1) material local que coincida de verdad
 *  2) si no hay, descarga fotos nuevas para esa búsqueda
 *  3) si tampoco, una foto genérica (nunca un clip o infografía de otro tema)
 */
async function resolverEscenas(
  plan: Plan,
  anotar: (linea: string) => void,
): Promise<Resuelta[]> {
  const escenas = (plan.escenas ?? []).filter(Boolean);
  if (escenas.length === 0) throw new Error("El plan no tiene escenas.");

  let material = escanear(PIPELINE);
  const usados = new Set<string>();
  const resueltas: Resuelta[] = [];

  let carpetaPrevia = "";
  let descargas = 0;

  for (const e of escenas) {
    const consulta = `${e.busqueda ?? ""} ${e.descripcion ?? ""}`.trim();

    let elegido = elegirMaterial(material, consulta, usados, {
      minimo: 2,
      evitarCarpeta: carpetaPrevia,
    });

    if (!elegido && consulta && descargas < 6) {
      descargas++;
      const ok = await descargarFotos(consulta, anotar);
      if (ok) {
        material = escanear(PIPELINE);
        elegido = elegirMaterial(material, consulta, usados, { minimo: 1 });
      }
    }

    if (!elegido) {
      elegido = elegirGenerico(material, usados, carpetaPrevia);
      if (elegido) anotar(`  escena "${consulta}": sin coincidencia, se usa material genérico`);
    }

    if (!elegido) continue;

    usados.add(elegido.ruta);
    carpetaPrevia = elegido.carpeta;

    resueltas.push({
      material: elegido,
      dur: Math.min(8, Math.max(2.5, Number(e.dur) || 5)),
      movimiento: e.movimiento === "out" ? "out" : e.movimiento === "none" ? "" : "in",
    });
  }

  if (resueltas.length === 0) throw new Error("No se pudo resolver ningún visual.");
  return resueltas;
}

/** Arma la config que entiende scripts/reel.ps1. */
export function construirConfig(
  plan: Plan,
  resueltas: Resuelta[],
  factor = 1,
): Record<string, unknown> {
  const visual: Array<Record<string, unknown>> = resueltas.map((r) => ({
    tipo: r.material.tipo,
    archivo: r.material.ruta,
    ...(r.material.tipo === "video" ? { desde: 0 } : {}),
    dur: r.dur,
    zoom: r.movimiento,
    modo: r.material.tipo === "foto" ? "blurfill" : "fill",
  }));

  // La última escena absorbe la diferencia de tiempo.
  visual[visual.length - 1].dur = null;

  const cierre = (plan.cierre ?? "").trim();
  const voz = (plan.vozTexto ?? "").trim();
  const vozTexto = cierre && !voz.includes(cierre) ? `${voz} ${cierre}` : voz;
  if (!vozTexto) throw new Error("El plan no tiene texto de voz.");

  // Los planos fijos no pueden sumar más que la voz (edge ≈ 13 caracteres/segundo).
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

/** Estimación de cuánto va a tardar el render (medida con reels reales). */
function estimarSegundos(plan: Plan): number {
  const voz = `${plan.vozTexto ?? ""} ${plan.cierre ?? ""}`.trim();
  const audio = Math.max(10, voz.length / 13);
  const escenas = Math.max(3, (plan.escenas ?? []).length);
  // Calibrado con dos renders reales (i3-7100U):
  //   13s / 4 escenas -> ~180s · 30s / 6 escenas -> ~548s
  // El montaje con zoompan es lo que más tarda. Preferimos sobreestimar.
  return Math.round(45 + audio * 12 + escenas * 20);
}

/** Lanza el render en segundo plano y devuelve el id del trabajo. */
export function iniciarRender(plan: Plan): EstadoTrabajo {
  const fecha = hoy();
  const id = `${fecha}-${slug(String(plan.titulo ?? "reel"))}-${Math.random().toString(36).slice(2, 6)}`;

  const trabajo: EstadoTrabajo = {
    id,
    estado: "encolado",
    progreso: 0,
    mensaje: "Encolado",
    log: [],
    iniciado: Date.now(),
    estimadoSegundos: estimarSegundos(plan),
  };
  trabajos.set(id, trabajo);

  const anotar = (linea: string) => {
    trabajo.log.push(linea);
    if (trabajo.log.length > 400) trabajo.log.shift();
    if (linea.startsWith("TOTAL") || linea.includes("FINAL:")) trabajo.progreso = 75;
    if (linea.includes("OK audio")) trabajo.progreso = 60;
  };

  void (async () => {
    try {
      trabajo.estado = "renderizando";
      trabajo.progreso = 5;
      trabajo.mensaje = "Eligiendo material para cada escena…";

      const dirGuiones = path.join(PIPELINE, "01-guiones", fecha);
      fs.mkdirSync(dirGuiones, { recursive: true });
      const configRel = `01-guiones/${fecha}/${id}.json`;
      const configAbs = path.join(PIPELINE, configRel);

      const resueltas = await resolverEscenas(plan, anotar);

      let factor = 1;
      let codigo = -1;
      let salidaRel = "";

      for (let intento = 0; intento < 3; intento++) {
        const cfg = construirConfig(plan, resueltas, factor);
        cfg.id = id;
        cfg.fecha = fecha;
        cfg.salida = `${id}.mp4`;
        salidaRel = `06-salida/${fecha}/${String(cfg.salida)}`;

        fs.writeFileSync(configAbs, JSON.stringify(cfg, null, 2), "utf8");
        trabajo.config = configRel;
        trabajo.mensaje =
          intento === 0 ? "Generando voz y montando el video…" : `Reintento ${intento}…`;
        trabajo.progreso = 20;

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
        anotar("→ Los planos no entraban en la voz: reintento con planos más cortos.");
        trabajo.progreso = 20;
      }

      if (codigo !== 0) {
        trabajo.estado = "error";
        trabajo.mensaje = `El render falló (código ${codigo}). Revisá el log.`;
        trabajo.terminado = Date.now();
        return;
      }

      trabajo.progreso = 85;
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
