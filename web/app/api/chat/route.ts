import { NextResponse } from "next/server";
import { env } from "@/lib/config";

type Msg = { role: "user" | "assistant"; text: string };

const SISTEMA = `Sos el asistente de MediaPilot, un panel que produce y publica video corto con IA.
Funciona para cualquier temática: autos, ciencia, historia, terror, comida, lo que pidan.

QUÉ HACE EL PANEL (tenelo presente siempre):
- El usuario pide un reel y el panel lo PRODUCE: guion -> voz -> visuales -> subtítulos -> render -> publicación.
- Los visuales salen de material con licencia (NASA, Unsplash, Pixabay, Pexels) y del archivo propio.
- Todavía NO hay modelo de generación de video: no prometas clips generados por IA.
- El video final se arma con el pipeline de FFmpeg del proyecto.
- Publicar siempre lo confirma el usuario.

CUANDO PIDEN UN REEL, UN VIDEO O UN SHORT:
Nunca devuelvas solo prosa ni un guion "listo para copiar" como si fuera el entregable.
Devolvés: UNA línea de encuadre + un bloque de plan de producción así:

\`\`\`plan
{
  "titulo": "texto corto para el título",
  "gancho": "LINEA 1|LINEA 2",
  "vozTexto": "guion completo tal como se va a narrar, sin acotaciones ni marcas de tiempo",
  "duracion": 40,
  "escenas": [
    { "n": 1, "descripcion": "qué se ve", "busqueda": "palabras en inglés para buscar el material", "dur": 5, "movimiento": "in" }
  ],
  "musica": "tipo de música de fondo que corresponde",
  "cierre": "pregunta final que provoca comentarios"
}
\`\`\`

Reglas del plan:
- 6 a 10 escenas, cada una de 3 a 7 segundos.
- La suma de "dur" tiene que dar la "duracion" declarada (más o menos 3s).
- "busqueda" siempre en inglés y concreta (ej: "empty night street fog", "old elevator dark").
- "gancho" de 2 líneas cortas, en mayúsculas y sin signos raros.
- "vozTexto" sin números escritos con dígitos cuando se leen raro: escribí "tres y siete" y no "3:07".
- El "cierre" NO es "¿te gustó?": es una pregunta que obliga a opinar o a elegir.

PARA TODO LO DEMÁS (títulos, descripciones, hashtags, dudas):
Respondés breve, en español neutro, máximo 6 líneas, listo para copiar.
No inventes datos del proyecto: si falta información, pedí lo mínimo.`;

function extraerPlan(texto: string): string | null {
  const m = texto.match(/```plan\s*([\s\S]*?)```/i);
  if (!m) return null;
  return m[1].trim();
}

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

type Turno = { role: "system" | "user" | "assistant"; content: string };

/** Proveedor principal: DeepSeek V4.1 Flash 1017 vía OpenRouter. */
async function conDeepSeek(
  historial: Turno[],
  promptSistema: string,
): Promise<{ texto: string; motor: string } | null> {
  const key = env("OPENROUTER_KEY");
  if (!key) return null;

  const modelo = env("DEEPSEEK_MODELO") || "deepseek/deepseek-v4.1-flash-1017";

  try {
    const res = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
        "HTTP-Referer": env("APP_URL") || "http://localhost:3000",
        "X-Title": "MediaPilot",
      },
      body: JSON.stringify({
        model: modelo,
        messages: [{ role: "system", content: promptSistema }, ...historial],
        max_tokens: 2000,
        temperature: 0.7,
      }),
    });

    if (!res.ok) return null;

    const data = (await res.json()) as {
      choices?: Array<{ message?: { content?: string } }>;
      error?: { message?: string };
    };

    const texto = data.choices?.[0]?.message?.content?.trim();
    if (!texto) return null;

    return { texto, motor: "DeepSeek V4.1 Flash" };
  } catch {
    return null;
  }
}

/** Respaldo: Gemini. */
async function conGemini(
  historial: Turno[],
  promptSistema: string,
): Promise<{ texto: string; motor: string } | null> {
  const key = env("GOOGLE_AI_KEY");
  if (!key) return null;

  const preferido = env("GEMINI_MODELO") || "gemini-3.5-flash";
  const modelos = Array.from(new Set([preferido, "gemini-3.5-flash", "gemini-flash-lite-latest"]));

  for (const modelo of modelos) {
    try {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${modelo}:generateContent?key=${key}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: promptSistema }] },
            contents: historial.map((m) => ({
              role: m.role === "assistant" ? "model" : "user",
              parts: [{ text: m.content }],
            })),
            generationConfig: { temperature: 0.7, maxOutputTokens: 2000 },
          }),
        },
      );

      if (!res.ok) continue;

      const data = (await res.json()) as {
        candidates?: Array<{ content?: { parts?: Array<{ text?: string }> } }>;
      };

      const texto = data.candidates?.[0]?.content?.parts?.map((p) => p.text || "").join("").trim();
      if (texto) return { texto, motor: `Gemini (${modelo})` };
    } catch {
      /* siguiente modelo */
    }
  }
  return null;
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
  const promptSistema = `${SISTEMA}\n\nContexto del proyecto: ${contexto || "sin datos"}`;

  const historial: Turno[] = messages.slice(-10).map((m) => ({
    role: m.role === "assistant" ? "assistant" : "user",
    content: m.text,
  }));

  const armar = (reply: string, motor: string, aviso?: string) =>
    NextResponse.json({ reply, motor, aviso, plan: extraerPlan(reply) });

  const principal = await conDeepSeek(historial, promptSistema);
  if (principal) return armar(principal.texto, principal.motor);

  const respaldo = await conGemini(historial, promptSistema);
  if (respaldo) return armar(respaldo.texto, respaldo.motor, "DeepSeek no respondió: se usó Gemini.");

  return armar(
    respuestaLocal(ultimo.text, contexto),
    "local",
    "Ningún modelo respondió: respuesta local.",
  );
}
