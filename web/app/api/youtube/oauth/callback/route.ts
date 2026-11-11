import { NextResponse } from "next/server";
import { env } from "@/lib/config";
import { readTokens, writeTokens } from "@/lib/tokens";
import { fetchChannel } from "@/lib/youtube";


export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const code = url.searchParams.get("code");
  const errorParam = url.searchParams.get("error");

  if (errorParam) {
    return NextResponse.redirect(`${origin}/?error=${encodeURIComponent(errorParam)}`);
  }
  if (!code) {
    return NextResponse.redirect(`${origin}/?error=${encodeURIComponent("Falta el código de Google")}`);
  }

  const redirectUri = env("YOUTUBE_REDIRECT_URI") || `${origin}/api/youtube/oauth/callback`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env("YOUTUBE_CLIENT_ID"),
      client_secret: env("YOUTUBE_CLIENT_SECRET"),
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });

  const data = (await res.json()) as {
    refresh_token?: string;
    access_token?: string;
    expires_in?: number;
    error_description?: string;
    error?: string;
  };

  if (!res.ok || !data.access_token) {
    return NextResponse.redirect(
      `${origin}/?error=${encodeURIComponent(data.error_description || data.error || "Google rechazó la autorización")}`,
    );
  }

  const prev = readTokens();
  writeTokens({
    refresh_token: data.refresh_token || prev.refresh_token,
    access_token: data.access_token,
    expires_at: Date.now() + (data.expires_in ?? 3600) * 1000,
  });

  try {
    const channel = await fetchChannel();
    writeTokens({ ...readTokens(), channel: channel ?? undefined });
  } catch {
    /* el canal se puede leer después */
  }

  return NextResponse.redirect(`${origin}/?conectado=1`);
}
