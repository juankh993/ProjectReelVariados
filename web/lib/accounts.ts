import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { DATA_DIR, TOKENS_FILE, ensureDirs } from "./config";

export type Cuenta = {
  id: string;
  sessionId: string; // "*" = cuenta del servidor, visible para todos
  channelId: string;
  title: string;
  thumbnail?: string;
  subscribers?: string;
  videos?: string;
  views?: string;
  refresh_token: string;
  access_token?: string;
  expires_at?: number;
  createdAt: string;
  shared?: boolean;
};

const ARCHIVO = path.join(DATA_DIR, "accounts.json");

export function leerCuentas(): Cuenta[] {
  try {
    ensureDirs();
    if (!fs.existsSync(ARCHIVO)) return migrar();
    const raw = fs.readFileSync(ARCHIVO, "utf8");
    const data = JSON.parse(raw) as Cuenta[];
    return Array.isArray(data) ? data : [];
  } catch {
    return [];
  }
}

export function guardarCuentas(cuentas: Cuenta[]) {
  ensureDirs();
  fs.writeFileSync(ARCHIVO, JSON.stringify(cuentas, null, 2), "utf8");
}

/** Importa el token viejo (un solo canal) como cuenta compartida del servidor. */
function migrar(): Cuenta[] {
  try {
    if (!fs.existsSync(TOKENS_FILE)) return [];
    const viejo = JSON.parse(fs.readFileSync(TOKENS_FILE, "utf8")) as {
      refresh_token?: string;
      channel?: { id: string; title: string; subscribers?: string; videos?: string; views?: string };
    };
    if (!viejo.refresh_token) return [];

    const cuenta: Cuenta = {
      id: crypto.randomBytes(8).toString("hex"),
      sessionId: "*",
      channelId: viejo.channel?.id ?? "",
      title: viejo.channel?.title ?? "Canal conectado",
      subscribers: viejo.channel?.subscribers,
      videos: viejo.channel?.videos,
      views: viejo.channel?.views,
      refresh_token: viejo.refresh_token,
      createdAt: new Date().toISOString(),
      shared: true,
    };
    guardarCuentas([cuenta]);
    return [cuenta];
  } catch {
    return [];
  }
}

/** Cuentas que puede ver una sesión: las suyas + las del servidor. */
export function cuentasDeSesion(sessionId: string): Cuenta[] {
  return leerCuentas().filter((c) => c.sessionId === sessionId || c.sessionId === "*");
}

export function crearCuenta(datos: Omit<Cuenta, "id" | "createdAt">): Cuenta {
  const cuentas = leerCuentas();
  const cuenta: Cuenta = {
    ...datos,
    id: crypto.randomBytes(8).toString("hex"),
    createdAt: new Date().toISOString(),
  };

  // Si el mismo canal ya estaba conectado por esta sesión, se actualiza.
  const idx = cuentas.findIndex(
    (c) => c.sessionId === datos.sessionId && c.channelId === datos.channelId,
  );
  if (idx >= 0) {
    cuentas[idx] = { ...cuentas[idx], ...cuenta, id: cuentas[idx].id };
    guardarCuentas(cuentas);
    return cuentas[idx];
  }

  cuentas.push(cuenta);
  guardarCuentas(cuentas);
  return cuenta;
}

export function borrarCuenta(id: string, sessionId: string): boolean {
  const cuentas = leerCuentas();
  const filtradas = cuentas.filter((c) => !(c.id === id && (c.sessionId === sessionId || c.sessionId === "*")));
  if (filtradas.length === cuentas.length) return false;
  guardarCuentas(filtradas);
  return true;
}

export function actualizarCuenta(id: string, cambios: Partial<Cuenta>) {
  const cuentas = leerCuentas();
  const idx = cuentas.findIndex((c) => c.id === id);
  if (idx < 0) return;
  cuentas[idx] = { ...cuentas[idx], ...cambios };
  guardarCuentas(cuentas);
}

/** Versión pública: sin tokens. */
export function publica(c: Cuenta) {
  return {
    id: c.id,
    channelId: c.channelId,
    title: c.title,
    thumbnail: c.thumbnail,
    subscribers: c.subscribers ?? "0",
    videos: c.videos ?? "0",
    views: c.views ?? "0",
    shared: Boolean(c.shared),
    createdAt: c.createdAt,
  };
}
