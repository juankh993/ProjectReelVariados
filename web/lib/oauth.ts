import { env } from "./config";

/** URI de retorno que hay que registrar en Google Cloud Console. */
export function redirectUri(request: Request): string {
  const origin = new URL(request.url).origin;
  return env("YOUTUBE_REDIRECT_URI") || `${origin}/api/youtube/oauth/callback`;
}
