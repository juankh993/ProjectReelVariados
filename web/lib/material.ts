import fs from "node:fs";
import path from "node:path";

const IMG = new Set([".jpg", ".jpeg", ".png", ".webp"]);
const VID = new Set([".mp4", ".mov", ".webm"]);

export type Material = {
  ruta: string; // relativa a la raíz del pipeline
  tipo: "foto" | "video";
  tokens: string[];
};

function normalizar(texto: string): string {
  return texto
    .toLowerCase()
    .replace(/\.[a-z0-9]+$/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
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
      salida.push({ ruta: rel, tipo, tokens: normalizar(rel).split(" ").filter(Boolean) });
    }
  };

  caminar(base);
  return salida;
}

/** Puntúa un material contra las palabras de la consulta. */
function puntuar(m: Material, palabras: string[]): number {
  let puntos = 0;
  for (const p of palabras) {
    if (p.length < 3) continue;
    if (m.tokens.some((t) => t === p)) puntos += 3;
    else if (m.tokens.some((t) => t.startsWith(p) || p.startsWith(t))) puntos += 2;
    else if (m.tokens.some((t) => t.includes(p))) puntos += 1;
  }
  return puntos;
}

/**
 * Elige el mejor material para una escena.
 * Si nada coincide, devuelve el primero no usado (así nunca queda una escena vacía).
 */
export function elegirMaterial(
  material: Material[],
  consulta: string,
  usados: Set<string>,
  preferir: "foto" | "video" | "cualquiera" = "cualquiera",
): Material | null {
  const palabras = normalizar(consulta).split(" ").filter((p) => p.length >= 3);

  const candidatos = material.filter(
    (m) => preferir === "cualquiera" || m.tipo === preferir,
  );
  if (candidatos.length === 0) return material[0] ?? null;

  let mejor: Material | null = null;
  let mejorPuntos = -1;

  for (const m of candidatos) {
    const base = puntuar(m, palabras);
    if (base === 0) continue;
    const puntos = base + (usados.has(m.ruta) ? 0 : 1.5);
    if (puntos > mejorPuntos) {
      mejorPuntos = puntos;
      mejor = m;
    }
  }

  if (mejor && mejorPuntos > 0) return mejor;

  // Sin coincidencias: el primero libre, si no el primero de todos.
  const libre = candidatos.find((m) => !usados.has(m.ruta));
  return libre ?? candidatos[0] ?? null;
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
