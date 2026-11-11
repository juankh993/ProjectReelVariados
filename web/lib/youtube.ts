import { env } from "./config";
import { readTokens, writeTokens, type Channel } from "./tokens";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const API = "https://www.googleapis.com/youtube/v3";

export const SCOPES = [
  "https://www.googleapis.com/auth/youtube.upload",
  "https://www.googleapis.com/auth/youtube.readonly",
].join(" ");

/** Devuelve un access_token válido (refresca si hace falta). */
export async function getAccessToken(): Promise<string> {
  const tokens = readTokens();

  if (tokens.access_token && tokens.expires_at && tokens.expires_at > Date.now() + 60_000) {
    return tokens.access_token;
  }
  if (!tokens.refresh_token) {
    throw new Error("No hay cuenta de YouTube conectada. Conectala desde el panel.");
  }

  const body = new URLSearchParams({
    client_id: env("YOUTUBE_CLIENT_ID"),
    client_secret: env("YOUTUBE_CLIENT_SECRET"),
    refresh_token: tokens.refresh_token,
    grant_type: "refresh_token",
  });

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  const data = (await res.json()) as {
    access_token?: string;
    expires_in?: number;
    error?: string;
    error_description?: string;
  };

  if (!res.ok || !data.access_token) {
    throw new Error(
      `No se pudo refrescar el token: ${data.error || res.status} ${data.error_description || ""}`.trim(),
    );
  }

  writeTokens({
    ...tokens,
    access_token: data.access_token,
    expires_at: Date.now() + (data.expires_in ?? 3600) * 1000,
  });

  return data.access_token;
}

export async function fetchChannel(): Promise<Channel | null> {
  const access = await getAccessToken();
  const res = await fetch(
    `${API}/channels?part=snippet,statistics&mine=true`,
    { headers: { Authorization: `Bearer ${access}` }, cache: "no-store" },
  );
  if (!res.ok) return null;

  const data = (await res.json()) as {
    items?: Array<{
      id: string;
      snippet: { title: string; thumbnails?: { default?: { url: string } } };
      statistics: { subscriberCount?: string; videoCount?: string; viewCount?: string };
    }>;
  };

  const item = data.items?.[0];
  if (!item) return null;

  return {
    id: item.id,
    title: item.snippet.title,
    subscribers: item.statistics.subscriberCount ?? "0",
    videos: item.statistics.videoCount ?? "0",
    views: item.statistics.viewCount ?? "0",
    thumbnail: item.snippet.thumbnails?.default?.url,
  };
}

export type UploadOptions = {
  title: string;
  description: string;
  tags: string[];
  privacy: "public" | "unlisted" | "private";
  fileName: string;
  bytes: Buffer;
  mimeType: string;
};

/** Subida resumible: crea la sesión y manda el archivo completo. */
export async function uploadVideo(opts: UploadOptions): Promise<{ id: string }> {
  const access = await getAccessToken();

  const initRes = await fetch(
    `${API.replace("/youtube/v3", "/upload/youtube/v3")}/videos?uploadType=resumable&part=snippet,status`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${access}`,
        "Content-Type": "application/json; charset=UTF-8",
        "X-Upload-Content-Length": String(opts.bytes.length),
        "X-Upload-Content-Type": opts.mimeType,
      },
      body: JSON.stringify({
        snippet: {
          title: opts.title,
          description: opts.description,
          tags: opts.tags,
          categoryId: "2",
        },
        status: {
          privacyStatus: opts.privacy,
          selfDeclaredMadeForKids: false,
        },
      }),
    },
  );

  if (!initRes.ok) {
    const txt = await initRes.text();
    throw new Error(`YouTube rechazó la creación del video: ${initRes.status} ${txt.slice(0, 300)}`);
  }

  const location = initRes.headers.get("location");
  if (!location) throw new Error("YouTube no devolvió la URL de subida.");

  const putRes = await fetch(location, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${access}`,
      "Content-Type": opts.mimeType,
      "Content-Length": String(opts.bytes.length),
    },
    body: new Uint8Array(opts.bytes),
  });

  const json = (await putRes.json()) as { id?: string; error?: { message?: string } };
  if (!putRes.ok || !json.id) {
    throw new Error(`Falló la subida: ${json.error?.message || putRes.status}`);
  }

  return { id: json.id };
}

export async function setThumbnail(videoId: string, bytes: Buffer, mimeType = "image/jpeg") {
  const access = await getAccessToken();
  const res = await fetch(
    `https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=${encodeURIComponent(videoId)}`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": mimeType },
      body: new Uint8Array(bytes),
    },
  );
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`No se pudo poner la miniatura: ${res.status} ${txt.slice(0, 200)}`);
  }
}
