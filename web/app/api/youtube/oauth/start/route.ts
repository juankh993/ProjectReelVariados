import { NextResponse } from "next/server";
import crypto from "node:crypto";
import { env, isConfigured } from "@/lib/config";
import { redirectUri } from "@/lib/oauth";
import { SCOPES } from "@/lib/youtube";

export async function GET(request: Request) {
  if (!isConfigured()) {
    const origin = new URL(request.url).origin;
    return NextResponse.redirect(
      `${origin}/?error=${encodeURIComponent(
        "Faltan YOUTUBE_CLIENT_ID y YOUTUBE_CLIENT_SECRET en .env.local",
      )}`,
    );
  }

  const state = crypto.randomBytes(16).toString("hex");

  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", env("YOUTUBE_CLIENT_ID"));
  url.searchParams.set("redirect_uri", redirectUri(request));
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", SCOPES);
  url.searchParams.set("access_type", "offline");
  // "consent" obliga a Google a devolver refresh_token siempre
  url.searchParams.set("prompt", "consent select_account");
  url.searchParams.set("include_granted_scopes", "true");
  url.searchParams.set("state", state);

  const res = NextResponse.redirect(url.toString());
  res.cookies.set("mp_oauth_state", state, {
    httpOnly: true,
    sameSite: "lax",
    path: "/",
    maxAge: 600,
  });
  return res;
}
