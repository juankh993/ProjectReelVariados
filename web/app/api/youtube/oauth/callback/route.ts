import { NextResponse } from "next/server";
import { cookies } from "next/headers";
import { env } from "@/lib/config";
import { redirectUri } from "@/lib/oauth";
import { getSessionId } from "@/lib/session";
import { crearCuenta } from "@/lib/accounts";
import { canalDe } from "@/lib/youtube";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const origin = url.origin;
  const code = url.searchParams.get("code");
  const errorParam = url.searchParams.get("error");
  const state = url.searchParams.get("state");

  if (errorParam) {
    return NextResponse.redirect(`${origin}/?error=${encodeURIComponent(errorParam)}`);
  }
  if (!code) {
    return NextResponse.redirect(`${origin}/?error=${encodeURIComponent("Falta el código de Google")}`);
  }

  const store = await cookies();
  const esperado = store.get("mp_oauth_state")?.value;
  if (esperado && state && esperado !== state) {
    return NextResponse.redirect(
      `${origin}/?error=${encodeURIComponent("La sesión de autorización no coincide. Probá de nuevo.")}`,
    );
  }

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env("YOUTUBE_CLIENT_ID"),
      client_secret: env("YOUTUBE_CLIENT_SECRET"),
      redirect_uri: redirectUri(request),
      grant_type: "authorization_code",
    }),
  });

  const data = (await res.json()) as {
    refresh_token?: string;
    access_token?: string;
    expires_in?: number;
    error?: string;
    error_description?: string;
  };

  if (!res.ok || !data.access_token) {
    return NextResponse.redirect(
      `${origin}/?error=${encodeURIComponent(
        data.error_description || data.error || "Google rechazó la autorización",
      )}`,
    );
  }

  if (!data.refresh_token) {
    return NextResponse.redirect(
      `${origin}/?error=${encodeURIComponent(
        "Google no devolvió el permiso permanente. Entrá a myaccount.google.com/permissions, quitá el acceso de la app y volvé a conectar.",
      )}`,
    );
  }

  const canal = await canalDe(data.access_token);
  const sessionId = await getSessionId();

  crearCuenta({
    sessionId,
    channelId: canal?.id ?? "desconocido",
    title: canal?.title ?? "Canal de YouTube",
    thumbnail: canal?.thumbnail,
    subscribers: canal?.subscribers,
    videos: canal?.videos,
    views: canal?.views,
    refresh_token: data.refresh_token,
    access_token: data.access_token,
    expires_at: Date.now() + (data.expires_in ?? 3600) * 1000,
  });

  const respuesta = NextResponse.redirect(`${origin}/?conectado=1`);
  respuesta.cookies.delete("mp_oauth_state");
  return respuesta;
}
