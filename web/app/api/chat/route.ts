import { NextResponse } from "next/server";
import { env } from "@/lib/config";


type Msg = { role: "user" | "assistant"; text: string };

const SISTEMA = `Sos el asistente de MediaPilot, un panel para producir y publicar video
de cualquier temática (autos, ciencia, comida, historia, lo que el usuario quiera).

Reglas:
- Respondés en español neutro, breve y concreto (máximo 6 líneas).
- Cuando te pidan un título, una descripción o hashtags, los das listos para copiar.
- No inventes datos del proyecto: si falta información, pedí lo mínimo necesario.
- Nunca digas que ya publicaste algo: la publicación siempre la confirma el usuario.
- Si te piden algo que requiere el backend (render, subir), explicá en una línea qué vas a hacer
  y qué necesita el usuario.`;

function respuestaLocal(texto: string, contexto: string): string {
  const t = texto.toLowerCase();

  if (/t[ií]tulo|titulo/.test(t)) {
    return "Decime el tema y el gancho principal y te armo 3 títulos: uno con número, uno con pregunta y uno directo. Los títulos de Shorts funcionan mejor por debajo de 60 caracteres.";
  }
  if (/descripci[oó]n/.test(t)) {
    return "Para la descripción necesito: tema del video, dato fuerte y la pregunta final. Con eso te la dejo lista con hashtags incluidos.";
  }
  if (/miniatura|portada/.test(t)) {
    return "Regla para miniaturas: un fotograma del propio video + el gancho en 2 líneas cortas. En vertical para Shorts, porque YouTube recorta las tarjetas al centro.";
  }
  if (/youtube/.test(t)) {
    return "Para YouTube preparo título, descripción, hashtags, visibilidad y miniatura. Después lo subís desde «Preparar publicación» y te pido confirmación antes de enviarlo.";
  }
  if (/instagram|tiktok|facebook/.test(t)) {
    return "En TikTok e Instagram manda el caption, no la voz: poné la pregunta en la primera línea. Los conectores están en la pestaña «Cuentas conectadas».";
  }
  if (/acortar|30 segundos|m[aá]s corto/.test(t)) {
    return "Para acortar: conservo el gancho de los primeros 2 segundos, un dato central y el cierre. Todo lo del medio se recorta. Decime el objetivo de duración exacto.";
  }
  if (/capcut/.test(t)) {
    return "Te puedo exportar el paquete para CapCut: MP4, audio por separado, subtítulos .srt, los clips originales y la miniatura, en una carpeta ordenada.";
  }

  const pistas: string[] = [];
  if (contexto.includes("video:si")) pistas.push("ya hay un video cargado");
  if (contexto.includes("video:no")) pistas.push("todavía no hay video cargado");

  return `Entendido. ${pistas.length ? `(${pistas.join(", ")}) ` : ""}Contame qué querés hacer con el proyecto y te lo dejo listo: guion, metadatos, miniatura o publicación.`;
}

export async function POST(request: Request) {
  let body: { messages?: Msg[]; context?: string };
  try {
    body = (await request.json()) as { messages?: Msg[]; context?: string };
  } catch {
    return NextResponse.json({ error: "JSON inválido" }, { status: 400 });
  }

  const messages = (body.messages || []).filter((m) => m && typeof m.text === "string");
  const ultimo = messages.filter((m) => m.role === "user").pop();
  if (!ultimo) return NextResponse.json({ error: "Falta el mensaje" }, { status: 400 });

  const contexto = body.context || "";
  const key = env("GOOGLE_AI_KEY");

  if (!key) {
    return NextResponse.json({
      reply: respuestaLocal(ultimo.text, contexto),
      motor: "local",
    });
  }

  const preferido = env("GEMINI_MODELO") || "gemini-3.5-flash";
  const modelos = Array.from(
    new Set([preferido, "gemini-3.5-flash", "gemini-flash-lite-latest"]),
  );

  let fallo = "";
  for (const modelo of modelos) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent?key=${key}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            systemInstruction: {
              parts: [{ text: `${SISTEMA}\n\nContexto del proyecto: ${contexto || "sin datos"}` }],
            },
            contents: messages.slice(-10).map((m) => ({
              role: m.role === "assistant" ? "model" : "user",
              parts: [{ text: m.text }],
            })),
            generationConfig: { temperature: 0.7, maxOutputTokens: 900 },
          }),
        },
      );

      if (!res.ok) {
        fallo = `${modelo}: ${res.status}`;
        continue;
      }

      const data = (await res.json()) as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      };

      const texto = data.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("").trim();
      if (!texto) {
        fallo = `${modelo}: respuesta vacía`;
        continue;
      }

      return NextResponse.json({ reply: texto, motor: modelo });
    } catch (error) {
      fallo = `${modelo}: ${error instanceof Error ? error.message : "error"}`;
    }
  }

  return NextResponse.json({
    reply: respuestaLocal(ultimo.text, contexto),
    motor: "local",
    aviso: `Gemini no respondió (${fallo})`,
  });
}
