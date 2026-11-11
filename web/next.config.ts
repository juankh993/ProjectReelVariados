import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // El panel lee y escribe archivos locales (tokens, subidas) y llama a APIs externas
  // en cada request: no queremos rutas "cacheadas" ni rutas prerenderizadas.
  cacheComponents: false,
};

export default nextConfig;
