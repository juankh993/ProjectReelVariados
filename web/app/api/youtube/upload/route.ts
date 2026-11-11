import { NextResponse } from "next/server";
import { getSessionId } from "@/lib/session";
import { cuentasDeSesion } from "@/lib/accounts";
import { accessTokenDe, ponerMiniatura, subirVideo } from "@/lib/youtube";

export const maxDuration = 300;

export async function POST(request: Request) {
  try {
    const form = await request.formData();
    const video = form.get("video");
    const title = String(form.get("title") || "").trim();
    const description = String(form.get("description") || "");
    const tagsRaw = String(form.get("tags") || "");
    const privacyRaw = String(form.get("privacy") || "public");
    const thumbnail = form.get("thumbnail");
    const accountId = String(form.get("accountId") || "");

    if (!(video instanceof File)) {
      return NextResponse.json({ error: "Falta el archivo de video." }, { status: 400 });
    }
    if (!title) {
      return NextResponse.json({ error: "El título es obligatorio." }, { status: 400 });
    }
    if (title.length > 100) {
      return NextResponse.json({ error: "El título supera los 100 caracteres." }, { status: 400 });
    }

    const sessionId = await getSessionId();
    const cuentas = cuentasDeSesion(sessionId);

    if (cuentas.length === 0) {
      return NextResponse.json(
        { error: "No hay ninguna cuenta de YouTube conectada. Conectala desde «Cuentas»." },
        { status: 400 },
      );
    }

    const cuenta = accountId ? cuentas.find((c) => c.id === accountId) : cuentas[0];
    if (!cuenta) {
      return NextResponse.json({ error: "Esa cuenta no está conectada en esta sesión." }, { status: 404 });
    }

    const privacy = privacyRaw === "private" || privacyRaw === "unlisted" ? privacyRaw : "public";
    const tags = tagsRaw
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean)
      .slice(0, 30);

    const accessToken = await accessTokenDe(cuenta);
    const bytes = Buffer.from(await video.arrayBuffer());

    const { id } = await subirVideo(accessToken, {
      title,
      description,
      tags,
      privacy,
      bytes,
      mimeType: video.type || "video/mp4",
    });

    let thumbnailWarning: string | null = null;
    if (thumbnail instanceof File && thumbnail.size > 0) {
      try {
        await ponerMiniatura(
          accessToken,
          id,
          Buffer.from(await thumbnail.arrayBuffer()),
          thumbnail.type || "image/jpeg",
        );
      } catch (error) {
        thumbnailWarning = error instanceof Error ? error.message : "No se pudo poner la miniatura";
      }
    }

    return NextResponse.json({
      ok: true,
      id,
      url: `https://youtu.be/${id}`,
      channel: cuenta.title,
      thumbnailWarning,
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Error inesperado" },
      { status: 500 },
    );
  }
}
