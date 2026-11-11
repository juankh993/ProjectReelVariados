import { NextResponse } from "next/server";
import { isConfigured } from "@/lib/config";
import { readTokens } from "@/lib/tokens";
import { fetchChannel } from "@/lib/youtube";


export async function GET() {
  const tokens = readTokens();
  const base = {
    configured: isConfigured(),
    connected: Boolean(tokens.refresh_token),
  };

  if (!base.connected) return NextResponse.json({ ...base, channel: null });

  try {
    const channel = await fetchChannel();
    return NextResponse.json({ ...base, channel });
  } catch (error) {
    return NextResponse.json({
      ...base,
      channel: tokens.channel ?? null,
      error: error instanceof Error ? error.message : "Error desconocido",
    });
  }
}
