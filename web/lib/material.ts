import fs from "node:fs";
import path from "node:path";

const IMG = new Set([".jpg", ".jpeg", ".png", ".webp"]);
const VID = new Set([".mp4", ".mov", ".webm"]);

export type Material = {
  ruta: string; // relativa a la raíz del pipeline
  tipo: "foto" | "video";
  carpeta: string;
  tokens: string[];
};

export type Opciones = {
  /** Puntaje mínimo para aceptar un material local. 0 = aceptar cualquiera. */
  minimo?: number;
  /** Carpeta usada en la escena anterior: se evita repetirla. */
  evitarCarpeta?: string;
  /** Tipos permitidos. */
  tipos?: Array<"foto" | "video">;
};

function normalizar(texto: string): string {
  return texto
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\.[a-z0-9]+$/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Palabras vacías: no aportan a la búsqueda y generan falsos positivos. */
const VACIAS = new Set([
  "the", "and", "with", "for", "from", "into", "over", "that", "this", "una", "uno",
  "unos", "unas", "con", "por", "para", "del", "los", "las", "que", "sobre", "como",
  "molto", "very", "close", "shot", "view", "dark", "night",
]);

export function palabrasClave(consulta: string): string[] {
  return normalizar(consulta)
    .split(" ")
    .filter((p) => p.length >= 3 && !VACIAS.has(p));
}

/** Recorre una carpeta y devuelve imágenes y videos con sus palabras clave. */
export function escanear(raiz: string, subcarpeta = "03-visual"): Material[] {
  const base = path.join(raiz, subcarpeta);
  const salida: Material[] = [];

  const caminar = (dir: string) => {
    let entradas: fs.Dirent[];
    try {
      entradas = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entradas) {
      const completo = path.join(dir, e.name);
      if (e.isDirectory()) {
        caminar(completo);
        continue;
      }
      const ext = path.extname(e.name).toLowerCase();
      const tipo = IMG.has(ext) ? "foto" : VID.has(ext) ? "video" : null;
      if (!tipo) continue;

      const rel = path.relative(raiz, completo).split(path.sep).join("/");
      salida.push({
        ruta: rel,
        tipo,
        carpeta: path.dirname(rel),
        tokens: normalizar(rel).split(" ").filter(Boolean),
      });
    }
  };

  caminar(base);
  return salida;
}

function puntuar(m: Material, palabras: string[]): number {
  let puntos = 0;
  for (const p of palabras) {
    if (m.tokens.some((t) => t === p)) puntos += 4;
    else if (m.tokens.some((t) => t.startsWith(p) || p.startsWith(t))) puntos += 2;
    else if (p.length >= 5 && m.tokens.some((t) => t.includes(p))) puntos += 1;
  }
  return puntos;
}

/**
 * Elige el mejor material local para una escena.
 * Devuelve null si nada alcanza el mínimo: así NO se mete material de otro tema.
 */
export function elegirMaterial(
  material: Material[],
  consulta: string,
  usados: Set<string>,
  opciones: Opciones = {},
): Material | null {
  const { minimo = 2, evitarCarpeta = "", tipos = ["foto", "video"] } = opciones;
  const palabras = palabrasClave(consulta);
  if (palabras.length === 0) return null;

  let mejor: Material | null = null;
  let mejorPuntos = 0;

  for (const m of material) {
    if (usados.has(m.ruta)) continue;
    if (!tipos.includes(m.tipo)) continue;

    let puntos = puntuar(m, palabras);
    if (puntos === 0) continue;

    // Variedad: no repetir la carpeta de la escena anterior.
    if (m.carpeta === evitarCarpeta) puntos -= 3;
    // Las fotos suelen verse mejor que los clips con texto quemado.
    if (m.tipo === "foto") puntos += 0.5;

    if (puntos > mejorPuntos) {
      mejorPuntos = puntos;
      mejor = m;
    }
  }

  return mejorPuntos >= minimo ? mejor : null;
}

/** Reserva: solo fotos de 03-visual/fotos (material genérico, sin infografías). */
export function elegirGenerico(
  material: Material[],
  usados: Set<string>,
  evitarCarpeta = "",
): Material | null {
  const fotos = material.filter((m) => m.tipo === "foto" && m.carpeta.startsWith("03-visual/fotos"));
  const libres = fotos.filter((m) => !usados.has(m.ruta));

  if (libres.length === 0) {
    const cualquiera = material.filter((m) => !usados.has(m.ruta));
    return cualquiera[0] ?? fotos[0] ?? material[0] ?? null;
  }

  // Preferir una carpeta distinta a la anterior.
  const distintas = libres.filter((m) => m.carpeta !== evitarCarpeta);
  const grupo = distintas.length ? distintas : libres;
  return grupo[Math.floor(Math.random() * grupo.length)];
}

/** Lista de pistas de música disponibles. */
export function musicaDisponible(raiz: string): string[] {
  const dir = path.join(raiz, "05-musica");
  try {
    return fs
      .readdirSync(dir)
      .filter((f) => [".mp3", ".wav", ".m4a"].includes(path.extname(f).toLowerCase()))
      .map((f) => `05-musica/${f}`);
  } catch {
    return [];
  }
}
