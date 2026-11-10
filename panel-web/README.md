# MediaPilot — panel web agnóstico

MVP visual del panel de producción multimedia. No está atado a Furia Nation,
FrutiReels ni a una temática concreta.

> **Rama:** todo el front + backend vive en `feature/panel-web`.
> `main` se queda solo con el pipeline de producción, sin la aplicación web.

## Ejecutar

Abrir `index.html` directamente en el navegador o servir la carpeta:

```powershell
python -m http.server 8870 --directory panel-web
```

Después visitar `http://localhost:8870`.

## Incluido en este MVP

- Dashboard responsive.
- Preview de video con scrubber.
- Formatos vertical, horizontal y cuadrado.
- Carga de videos y biblioteca local de assets.
- Chat de demostración con acciones contextuales.
- Proyectos guardados en `localStorage`.
- Calendario y cuentas sociales como interfaz inicial.
- Diseño preparado para conectar OAuth y backend.

## Próxima fase técnica

1. API segura para proyectos y archivos.
2. Render FFmpeg en worker.
3. Chat conectado a un proveedor LLM configurable.
4. OAuth real para YouTube.
5. Exportación CapCut: MP4, SRT, audio, assets y manifest.
6. Conectores Meta y TikTok sujetos a sus requisitos de API.

Las conexiones reales no deben implementarse guardando tokens en el navegador.

## Llaves y credenciales

El listado completo de claves que necesita la app (YouTube, Meta, TikTok,
Telegram, Pixabay, Pexels, Unsplash, Freesound, Google AI, OpenRouter, Runway,
S3, Redis) está documentado en **`.env.example`**, en la raíz del repo.

```powershell
Copy-Item .env.example .env
```

- `.env` está en `.gitignore`: **nunca** se versiona.
- Todo es opcional por módulo: el panel funciona sin ninguna clave.
- Las claves reales del pipeline actual siguen en archivos `*.key`
  (`*.key` también está ignorado por git).
