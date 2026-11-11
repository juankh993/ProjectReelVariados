import { env } from "./config";
import { actualizarCuenta, type Cuenta } from "./accounts";

const TOKEN_URL = "https://oauth2.googleapis.com/token";
const API = "https://www.googleapis.com/youtube/v3";

export const SCOPES = [
  "https://www.googleapis.com/auth/youtube.upload",
  "https://www.googleapis.com/auth/youtube.readonly",
].join(" ");

export type CanalInfo = {
  id: string;
  title: string;
  thumbnail?: string;
  subscribers: string;
  videos: string;
  views: string;
};

/** Refresca y devuelve un access_token para ESA cuenta. */
export async function accessTokenDe(cuenta: Cuenta): Promise<string> {
  if (cuenta.access_token && cuenta.expires_at && cuenta.expires_at > Date.now() + 60_000) {
    return cuenta.access_token;
  }

  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env("YOUTUBE_CLIENT_ID"),
      client_secret: env("YOUTUBE_CLIENT_SECRET"),
      refresh_token: cuenta.refresh_token,
      grant_type: "refresh_token",
    }),
  });

  const data = (await res.json()) as {
    access_token?: string;
    expires_in?: number;
    error?: string;
    error_description?: string;
  };

  if (!res.ok || !data.access_token) {
    throw new Error(
      `La cuenta "${cuenta.title}" necesita reconectarse (${data.error || res.status}).`,
    );
  }

  const expira = Date.now() + (data.expires_in ?? 3600) * 1000;
  actualizarCuenta(cuenta.id, { access_token: data.access_token, expires_at: expira });

  return data.access_token;
}

export async function canalDe(accessToken: string): Promise<CanalInfo | null> {
  const res = await fetch(`${API}/channels?part=snippet,statistics&mine=true`, {
    headers: { Authorization: `Bearer ${accessToken}` },
    cache: "no-store",
  });
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
    thumbnail: item.snippet.thumbnails?.default?.url,
    subscribers: item.statistics.subscriberCount ?? "0",
    videos: item.statistics.videoCount ?? "0",
    views: item.statistics.viewCount ?? "0",
  };
}

export type UploadOptions = {
  title: string;
  description: string;
  tags: string[];
  privacy: "public" | "unlisted" | "private";
  bytes: Buffer;
  mimeType: string;
};

export async function subirVideo(
  accessToken: string,
  opts: UploadOptions,
): Promise<{ id: string }> {
  const initRes = await fetch(
    `https://www.googleapis.com/upload/youtube/v3/videos?uploadType=resumable&part=snippet,status`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
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
        status: { privacyStatus: opts.privacy, selfDeclaredMadeForKids: false },
      }),
    },
  );

  if (!initRes.ok) {
    const txt = await initRes.text();
    throw new Error(`YouTube rechazó el video: ${initRes.status} ${txt.slice(0, 300)}`);
  }

  const location = initRes.headers.get("location");
  if (!location) throw new Error("YouTube no devolvió la URL de subida.");

  const putRes = await fetch(location, {
    method: "PUT",
    headers: {
      Authorization: `Bearer ${accessToken}`,
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

export async function ponerMiniatura(
  accessToken: string,
  videoId: string,
  bytes: Buffer,
  mimeType = "image/jpeg",
) {
  const res = await fetch(
    `https://www.googleapis.com/upload/youtube/v3/thumbnails/set?videoId=${encodeURIComponent(videoId)}`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": mimeType },
      body: new Uint8Array(bytes),
    },
  );
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`No se pudo poner la miniatura: ${res.status} ${txt.slice(0, 200)}`);
  }
}
