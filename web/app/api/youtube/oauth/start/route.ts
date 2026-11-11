import { NextResponse } from "next/server";
import { env, isConfigured } from "@/lib/config";
import { SCOPES } from "@/lib/youtube";


export async function GET(request: Request) {
  if (!isConfigured()) {
    return NextResponse.json(
      {
        error:
          "Faltan YOUTUBE_CLIENT_ID y YOUTUBE_CLIENT_SECRET en .env. Copiá .env.example a .env y completalos.",
      },
      { status: 400 },
    );
  }

  const origin = new URL(request.url).origin;
  const redirectUri = env("YOUTUBE_REDIRECT_URI") || `${origin}/api/youtube/oauth/callback`;

  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", env("YOUTUBE_CLIENT_ID"));
  url.searchParams.set("redirect_uri", redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", SCOPES);
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("include_granted_scopes", "true");

  return NextResponse.redirect(url.toString());
}
