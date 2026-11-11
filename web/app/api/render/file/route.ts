import fs from "node:fs";
import { NextResponse } from "next/server";
import { obtenerTrabajo, resolverVideo } from "@/lib/render";

export async function GET(request: Request) {
  const id = new URL(request.url).searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Falta el id" }, { status: 400 });

  const trabajo = obtenerTrabajo(id);
  if (!trabajo?.video) return NextResponse.json({ error: "Todavía no hay video" }, { status: 404 });

  const abs = resolverVideo(trabajo.video);
  if (!abs) return NextResponse.json({ error: "Archivo no encontrado" }, { status: 404 });

  const datos = fs.readFileSync(abs);
  return new NextResponse(new Uint8Array(datos), {
    headers: {
      "Content-Type": "video/mp4",
      "Content-Length": String(datos.length),
      "Cache-Control": "no-store",
    },
  });
}
