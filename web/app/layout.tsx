import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "MediaPilot — panel de contenido",
  description: "Producción, previsualización y publicación de video para cualquier temática.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="es">
      <body>{children}</body>
    </html>
  );
}
