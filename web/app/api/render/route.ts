import { NextResponse } from "next/server";
import { iniciarRender, obtenerTrabajo, type Plan } from "@/lib/render";

export const maxDuration = 900;

function parsearPlan(entrada: unknown): Plan {
  if (typeof entrada === "string") {
    const limpio = entrada.trim();
    const bloque = limpio.match(/```plan\s*([\s\S]*?)```/i);
    return JSON.parse(bloque ? bloque[1] : limpio) as Plan;
  }
  if (entrada && typeof entrada === "object") return entrada as Plan;
  throw new Error("Plan inválido");
}

export async function POST(request: Request) {
  try {
    const body = (await request.json()) as { plan?: unknown };
    const plan = parsearPlan(body.plan);
    const trabajo = iniciarRender(plan);
    return NextResponse.json({ id: trabajo.id, estado: trabajo.estado });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "No se pudo iniciar el render" },
      { status: 400 },
    );
  }
}

export async function GET(request: Request) {
  const id = new URL(request.url).searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Falta el id" }, { status: 400 });

  const trabajo = obtenerTrabajo(id);
  if (!trabajo) return NextResponse.json({ error: "Trabajo no encontrado" }, { status: 404 });

  return NextResponse.json({
    id: trabajo.id,
    estado: trabajo.estado,
    progreso: trabajo.progreso,
    mensaje: trabajo.mensaje,
    video: trabajo.video ?? null,
    config: trabajo.config ?? null,
    log: trabajo.log.slice(-12),
  });
}
