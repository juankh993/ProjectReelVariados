import { cookies } from "next/headers";
import crypto from "node:crypto";

export const SESSION_COOKIE = "mp_sid";
const UN_ANIO = 60 * 60 * 24 * 365;

/**
 * Identificador de sesión del navegador.
 * Permite que cada usuario que entra al panel conecte SU propia cuenta de YouTube
 * sin pisar la de los demás.
 */
export async function getSessionId(): Promise<string> {
  const store = await cookies();
  const existente = store.get(SESSION_COOKIE)?.value;
  if (existente) return existente;

  const nuevo = crypto.randomBytes(16).toString("hex");
  try {
    store.set(SESSION_COOKIE, nuevo, {
      httpOnly: true,
      sameSite: "lax",
      path: "/",
      maxAge: UN_ANIO,
    });
  } catch {
    // En algunos contextos (render estático) no se puede escribir la cookie.
  }
  return nuevo;
}
