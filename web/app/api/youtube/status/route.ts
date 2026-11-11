import { NextResponse } from "next/server";
import { isConfigured } from "@/lib/config";
import { getSessionId } from "@/lib/session";
import { cuentasDeSesion, publica, borrarCuenta, leerCuentas, guardarCuentas, actualizarCuenta } from "@/lib/accounts";
import { redirectUri } from "@/lib/oauth";
import { accessTokenDe, canalDe } from "@/lib/youtube";

export async function GET(request: Request) {
  const sessionId = await getSessionId();
  let cuentas = cuentasDeSesion(sessionId);

  // Si una cuenta migrada no tiene datos del canal, se completan ahora.
  for (const c of cuentas) {
    if (c.channelId) continue;
    try {
      const token = await accessTokenDe(c);
      const info = await canalDe(token);
      if (info) {
        actualizarCuenta(c.id, {
          channelId: info.id,
          title: info.title,
          thumbnail: info.thumbnail,
          subscribers: info.subscribers,
          videos: info.videos,
          views: info.views,
        });
      }
    } catch {
      /* si falla, se muestra como está */
    }
  }
  cuentas = cuentasDeSesion(sessionId);

  return NextResponse.json({
    configured: isConfigured(),
    redirectUri: redirectUri(request),
    accounts: cuentas.map(publica),
    connected: cuentas.length > 0,
  });
}

/** Desconectar una cuenta (DELETE y POST por comodidad). */
export async function DELETE(request: Request) {
  const sessionId = await getSessionId();
  const { searchParams } = new URL(request.url);
  const id = searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Falta el id" }, { status: 400 });

  const ok = borrarCuenta(id, sessionId);
  return NextResponse.json({ ok, accounts: cuentasDeSesion(sessionId).map(publica) });
}

export async function POST(request: Request) {
  const sessionId = await getSessionId();
  let id = "";
  try {
    const body = (await request.json()) as { id?: string };
    id = String(body.id || "");
  } catch {
    id = new URL(request.url).searchParams.get("id") || "";
  }

  if (!id) return NextResponse.json({ error: "Falta el id" }, { status: 400 });

  if (id === "__all__") {
    const mias = leerCuentas().filter((c) => c.sessionId === sessionId);
    guardarCuentas(leerCuentas().filter((c) => c.sessionId !== sessionId));
    return NextResponse.json({ ok: true, removed: mias.length });
  }

  const ok = borrarCuenta(id, sessionId);
  return NextResponse.json({ ok, accounts: cuentasDeSesion(sessionId).map(publica) });
}
