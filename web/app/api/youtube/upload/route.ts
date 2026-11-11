import { NextResponse } from "next/server";
import { setThumbnail, uploadVideo } from "@/lib/youtube";

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

    if (!(video instanceof File)) {
      return NextResponse.json({ error: "Falta el archivo de video." }, { status: 400 });
    }
    if (!title) {
      return NextResponse.json({ error: "El título es obligatorio." }, { status: 400 });
    }
    if (title.length > 100) {
      return NextResponse.json({ error: "El título supera los 100 caracteres." }, { status: 400 });
    }

    const privacy =
      privacyRaw === "private" || privacyRaw === "unlisted" ? privacyRaw : "public";

    const tags = tagsRaw
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean)
      .slice(0, 30);

    const bytes = Buffer.from(await video.arrayBuffer());

    const { id } = await uploadVideo({
      title,
      description,
      tags,
      privacy,
      fileName: video.name,
      bytes,
      mimeType: video.type || "video/mp4",
    });

    let thumbnailWarning: string | null = null;
    if (thumbnail instanceof File && thumbnail.size > 0) {
      try {
        await setThumbnail(id, Buffer.from(await thumbnail.arrayBuffer()), thumbnail.type || "image/jpeg");
      } catch (error) {
        thumbnailWarning = error instanceof Error ? error.message : "No se pudo subir la miniatura";
      }
    }

    return NextResponse.json({
      ok: true,
      id,
      url: `https://youtu.be/${id}`,
      thumbnailWarning,
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Error inesperado" },
      { status: 500 },
    );
  }
}
