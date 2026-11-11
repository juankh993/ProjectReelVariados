import fs from "node:fs";
import { TOKENS_FILE, ensureDirs } from "./config";

export type Channel = {
  id: string;
  title: string;
  subscribers: string;
  videos: string;
  views: string;
  thumbnail?: string;
};

export type TokenStore = {
  refresh_token?: string;
  access_token?: string;
  expires_at?: number;
  channel?: Channel;
};

export function readTokens(): TokenStore {
  try {
    if (!fs.existsSync(TOKENS_FILE)) return {};
    return JSON.parse(fs.readFileSync(TOKENS_FILE, "utf8")) as TokenStore;
  } catch {
    return {};
  }
}

export function writeTokens(tokens: TokenStore) {
  ensureDirs();
  fs.writeFileSync(TOKENS_FILE, JSON.stringify(tokens, null, 2), "utf8");
}
