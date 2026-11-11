import fs from "node:fs";
import path from "node:path";

/** Raíz del proyecto Next (web/) */
export const ROOT = process.cwd();
export const DATA_DIR = path.join(ROOT, "data");
export const UPLOAD_DIR = path.join(DATA_DIR, "uploads");
export const TOKENS_FILE = path.join(DATA_DIR, "tokens.json");

export function ensureDirs() {
  for (const dir of [DATA_DIR, UPLOAD_DIR]) {
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  }
}

export function env(name: string): string {
  return (process.env[name] || "").trim();
}

export function envOr(name: string, fallback: string): string {
  const v = env(name);
  return v || fallback;
}

export function isConfigured(): boolean {
  return Boolean(env("YOUTUBE_CLIENT_ID") && env("YOUTUBE_CLIENT_SECRET"));
}
