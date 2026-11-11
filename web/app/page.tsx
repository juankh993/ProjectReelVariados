"use client";

import { useCallback, useEffect, useRef, useState } from "react";

type Vista = "estudio" | "proyectos" | "calendario" | "cuentas";
type Mensaje = { role: "user" | "assistant"; text: string };
type Asset = { id: string; name: string; size: number; type: string };
type Formato = "vertical" | "horizontal" | "cuadrado";

type Cuenta = {
  id: string;
  channelId: string;
  title: string;
  thumbnail?: string;
  subscribers: string;
  videos: string;
  views: string;
  shared?: boolean;
};

type EstadoYT = {
  configured: boolean;
  connected: boolean;
  redirectUri?: string;
  accounts: Cuenta[];
};

type Resultado = {
  ok: true;
  id: string;
  url: string;
  channel?: string;
  thumbnailWarning?: string | null;
};

const FORMATO_ASPECTO: Record<Formato, string> = {
  vertical: "9 / 16",
  horizontal: "16 / 9",
  cuadrado: "1 / 1",
};

function mmss(v: number) {
  if (!Number.isFinite(v)) return "00:00";
  const m = Math.floor(v / 60);
  const s = Math.floor(v % 60);
  return `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function peso(bytes: number) {
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
}

export default function Page() {
  const [vista, setVista] = useState<Vista>("estudio");
  const [proyecto, setProyecto] = useState("Mi primer proyecto");
  const [formato, setFormato] = useState<Formato>("vertical");

  const [video, setVideo] = useState<File | null>(null);
  const [videoUrl, setVideoUrl] = useState<string | null>(null);
  const [assets, setAssets] = useState<Asset[]>([]);
  const [duracion, setDuracion] = useState(0);
  const [actual, setActual] = useState(0);

  const [chat, setChat] = useState<Mensaje[]>([
    {
      role: "assistant",
      text: "Hola. Puedo ayudarte a preparar el video, escribir el guion, armar los metadatos o dejarlo listo para publicar. ¿Qué querés hacer?",
    },
  ]);
  const [entrada, setEntrada] = useState("");
  const [pensando, setPensando] = useState(false);
  const [motor, setMotor] = useState<string>("");

  const [yt, setYt] = useState<EstadoYT | null>(null);
  const [mostrarGuia, setMostrarGuia] = useState(false);
  const [modal, setModal] = useState(false);
  const [titulo, setTitulo] = useState("");
  const [descripcion, setDescripcion] = useState("");
  const [tags, setTags] = useState("shorts");
  const [privacidad, setPrivacidad] = useState<"public" | "unlisted" | "private">("public");
  const [miniatura, setMiniatura] = useState<File | null>(null);
  const [cuentaSel, setCuentaSel] = useState<string>("");
  const [subiendo, setSubiendo] = useState(false);
  const [resultado, setResultado] = useState<Resultado | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [toast, setToast] = useState<{ texto: string; error?: boolean } | null>(null);

  const videoRef = useRef<HTMLVideoElement | null>(null);
  const inputVideo = useRef<HTMLInputElement | null>(null);
  const inputAssets = useRef<HTMLInputElement | null>(null);
  const inputMini = useRef<HTMLInputElement | null>(null);

  const avisar = useCallback((texto: string, esError = false) => {
    setToast({ texto, error: esError });
    window.setTimeout(() => setToast(null), 4500);
  }, []);

  const cargarEstado = useCallback(async () => {
    try {
      const res = await fetch("/api/youtube/status", { cache: "no-store" });
      const data = (await res.json()) as EstadoYT;
      setYt(data);
      setCuentaSel((prev) => (prev && data.accounts.some((a) => a.id === prev) ? prev : data.accounts[0]?.id ?? ""));
    } catch {
      setYt({ configured: false, connected: false, accounts: [] });
    }
  }, []);

  useEffect(() => {
    cargarEstado();
    const params = new URLSearchParams(window.location.search);
    if (params.get("conectado")) {
      avisar("Cuenta de YouTube conectada");
      setVista("cuentas");
      window.history.replaceState({}, "", "/");
    }
    const err = params.get("error");
    if (err) {
      avisar(decodeURIComponent(err), true);
      setVista("cuentas");
      window.history.replaceState({}, "", "/");
    }
  }, [avisar, cargarEstado]);

  useEffect(() => {
    return () => {
      if (videoUrl) URL.revokeObjectURL(videoUrl);
    };
  }, [videoUrl]);

  function elegirVideo(file: File | null) {
    if (!file) return;
    if (videoUrl) URL.revokeObjectURL(videoUrl);
    setVideo(file);
    setVideoUrl(URL.createObjectURL(file));
    setResultado(null);
    setError(null);
    if (!titulo) setTitulo(file.name.replace(/\.[^.]+$/, "").slice(0, 95));
  }

  function agregarAssets(lista: FileList | null) {
    if (!lista) return;
    const nuevos = Array.from(lista).map((f) => ({
      id: `${f.name}-${f.size}-${f.lastModified}`,
      name: f.name,
      size: f.size,
      type: f.type.split("/")[0] || "archivo",
    }));
    setAssets((prev) => {
      const ids = new Set(prev.map((a) => a.id));
      return [...prev, ...nuevos.filter((n) => !ids.has(n.id))];
    });
  }

  async function enviar(texto: string) {
    const limpio = texto.trim();
    if (!limpio || pensando) return;

    const historial: Mensaje[] = [...chat, { role: "user", text: limpio }];
    setChat(historial);
    setEntrada("");
    setPensando(true);

    const contexto = [
      `proyecto:${proyecto}`,
      `formato:${formato}`,
      `video:${video ? "si" : "no"}`,
      `assets:${assets.length}`,
      `canales:${yt?.accounts.length ?? 0}`,
    ].join(" | ");

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: historial, context: contexto }),
      });
      const data = (await res.json()) as { reply?: string; error?: string; motor?: string };
      setChat((prev) => [
        ...prev,
        { role: "assistant", text: data.reply || data.error || "No pude responder." },
      ]);
      if (data.motor) setMotor(data.motor);
    } catch {
      setChat((prev) => [
        ...prev,
        { role: "assistant", text: "No pude conectar con el asistente. Revisá la consola del servidor." },
      ]);
    } finally {
      setPensando(false);
    }
  }

  async function publicar() {
    if (!video) return setError("Primero cargá un video en la preview.");
    if (!titulo.trim()) return setError("El título es obligatorio.");
    if (!cuentaSel) return setError("Conectá una cuenta de YouTube primero.");

    setSubiendo(true);
    setError(null);
    setResultado(null);

    const fd = new FormData();
    fd.append("video", video);
    fd.append("title", titulo.trim());
    fd.append("description", descripcion);
    fd.append("tags", tags);
    fd.append("privacy", privacidad);
    fd.append("accountId", cuentaSel);
    if (miniatura) fd.append("thumbnail", miniatura);

    try {
      const res = await fetch("/api/youtube/upload", { method: "POST", body: fd });
      const data = (await res.json()) as Resultado & { error?: string };
      if (!res.ok || !data.ok) setError(data.error || "Falló la subida.");
      else {
        setResultado(data);
        avisar("Video publicado en YouTube");
      }
    } catch {
      setError("No se pudo conectar con el servidor.");
    } finally {
      setSubiendo(false);
    }
  }

  async function desconectar(id: string, tituloCanal: string) {
    if (!window.confirm(`¿Desconectar "${tituloCanal}" de este panel?`)) return;
    try {
      const res = await fetch("/api/youtube/status", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id }),
      });
      const data = (await res.json()) as { accounts?: Cuenta[] };
      setYt((prev) => (prev ? { ...prev, accounts: data.accounts ?? [], connected: (data.accounts ?? []).length > 0 } : prev));
      avisar("Cuenta desconectada");
    } catch {
      avisar("No se pudo desconectar", true);
    }
  }

  const cuentas = yt?.accounts ?? [];
  const conectado = cuentas.length > 0;

  return (
    <div className="layout">
      <aside className="sidebar">
        <div className="brand">
          <span className="brand-mark">✦</span>
          <span>MediaPilot</span>
        </div>
        <nav>
          {(
            [
              ["estudio", "▣", "Estudio"],
              ["proyectos", "◫", "Proyectos"],
              ["calendario", "◷", "Calendario"],
              ["cuentas", "◎", "Cuentas"],
            ] as Array<[Vista, string, string]>
          ).map(([id, ico, label]) => (
            <button
              key={id}
              className={`nav-item${vista === id ? " active" : ""}`}
              onClick={() => setVista(id)}
            >
              <span className="ico">{ico}</span>
              <span>{label}</span>
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <span className={`dot ${conectado ? "on" : "off"}`} />
          {conectado
            ? cuentas.length === 1
              ? cuentas[0].title
              : `${cuentas.length} canales conectados`
            : "YouTube sin conectar"}
        </div>
      </aside>

      <main className="main">
        <header className="topbar">
          <div>
            <p className="eyebrow">CENTRO DE PRODUCCIÓN</p>
            <h1>
              {vista === "estudio" && "Estudio"}
              {vista === "proyectos" && "Proyectos"}
              {vista === "calendario" && "Calendario"}
              {vista === "cuentas" && "Cuentas conectadas"}
            </h1>
          </div>
          {vista === "estudio" && (
            <button
              className="button primary"
              onClick={() => {
                if (!video) return avisar("Cargá un video para continuar", true);
                if (!conectado) {
                  avisar("Primero conectá tu cuenta de YouTube", true);
                  setVista("cuentas");
                  return;
                }
                setModal(true);
              }}
            >
              Publicar en YouTube →
            </button>
          )}
        </header>

        {vista === "estudio" && (
          <>
            {!conectado && (
              <div className="alert warn" style={{ marginTop: 0, marginBottom: 14 }}>
                Todavía no conectaste tu cuenta de YouTube.{" "}
                <strong
                  style={{ cursor: "pointer", textDecoration: "underline" }}
                  onClick={() => setVista("cuentas")}
                >
                  Conectala acá
                </strong>{" "}
                para poder publicar.
              </div>
            )}

            <div className="project-strip">
              <div style={{ flex: 1, minWidth: 220 }}>
                <label>PROYECTO ACTUAL</label>
                <input value={proyecto} onChange={(e) => setProyecto(e.target.value)} />
              </div>
              <div>
                <label>FORMATO</label>
                <select value={formato} onChange={(e) => setFormato(e.target.value as Formato)}>
                  <option value="vertical">Vertical 9:16</option>
                  <option value="horizontal">Horizontal 16:9</option>
                  <option value="cuadrado">Cuadrado 1:1</option>
                </select>
              </div>
              <div style={{ fontSize: 12, color: "var(--muted)" }}>
                <span className={`dot ${conectado ? "on" : "off"}`} />
                {conectado ? "Listo para publicar" : "Sin canal conectado"}
              </div>
            </div>

            <div className="studio-grid">
              <section className="card">
                <div className="card-head">
                  <div>
                    <h2>Preview</h2>
                    <p>{video ? video.name : "Todavía no hay video"}</p>
                  </div>
                  <button className="button ghost" onClick={() => inputVideo.current?.click()}>
                    {video ? "Cambiar" : "＋ Añadir video"}
                  </button>
                  <input
                    ref={inputVideo}
                    type="file"
                    accept="video/*"
                    hidden
                    onChange={(e) => elegirVideo(e.target.files?.[0] ?? null)}
                  />
                </div>

                <div className="preview-stage">
                  <div className="video-shell" style={{ aspectRatio: FORMATO_ASPECTO[formato] }}>
                    {videoUrl ? (
                      <video
                        ref={videoRef}
                        src={videoUrl}
                        controls
                        playsInline
                        onLoadedMetadata={(e) => setDuracion(e.currentTarget.duration)}
                        onTimeUpdate={(e) => setActual(e.currentTarget.currentTime)}
                      />
                    ) : (
                      <div className="empty-preview">
                        <div className="play-icon">▶</div>
                        <strong>Subí un video para empezar</strong>
                        <small>MP4, MOV o WEBM · cualquier temática</small>
                        <button
                          className="button secondary"
                          style={{ marginTop: 8 }}
                          onClick={() => inputVideo.current?.click()}
                        >
                          Elegir archivo
                        </button>
                      </div>
                    )}
                  </div>
                </div>

                <div className="timeline">
                  <span>{mmss(actual)}</span>
                  <input
                    type="range"
                    min={0}
                    max={100}
                    value={duracion ? (actual / duracion) * 100 : 0}
                    onChange={(e) => {
                      if (videoRef.current && duracion) {
                        videoRef.current.currentTime = (Number(e.target.value) / 100) * duracion;
                      }
                    }}
                  />
                  <span>{mmss(duracion)}</span>
                </div>
              </section>

              <section className="card chat-card">
                <div className="card-head">
                  <div>
                    <h2>Asistente</h2>
                    <p>{motor || "DeepSeek V4.1 Flash"}</p>
                  </div>
                  <span className="badge gray">IA</span>
                </div>

                <div className="chat-messages">
                  {chat.map((m, i) => (
                    <div key={i} className={`message ${m.role}`}>
                      {m.text}
                    </div>
                  ))}
                  {pensando && <div className="message assistant">…</div>}
                  {chat.length <= 2 && (
                    <div className="suggestions">
                      <button onClick={() => enviar("Proponé 3 títulos para este video")}>
                        Proponer títulos
                      </button>
                      <button onClick={() => enviar("Escribí la descripción con hashtags")}>
                        Descripción
                      </button>
                      <button onClick={() => enviar("¿Qué miniatura me conviene?")}>
                        Miniatura
                      </button>
                    </div>
                  )}
                </div>

                <form
                  className="chat-form"
                  onSubmit={(e) => {
                    e.preventDefault();
                    enviar(entrada);
                  }}
                >
                  <input
                    value={entrada}
                    onChange={(e) => setEntrada(e.target.value)}
                    placeholder="Escribí una instrucción..."
                  />
                  <button className="send" type="submit" disabled={pensando}>
                    ➤
                  </button>
                </form>
              </section>
            </div>

            <section className="card assets-card">
              <div className="card-head">
                <div>
                  <h2>Activos del proyecto</h2>
                  <p>
                    {assets.length} archivo{assets.length === 1 ? "" : "s"}
                  </p>
                </div>
                <button className="button secondary" onClick={() => inputAssets.current?.click()}>
                  ＋ Añadir archivos
                </button>
                <input
                  ref={inputAssets}
                  type="file"
                  multiple
                  accept="video/*,image/*,audio/*"
                  hidden
                  onChange={(e) => agregarAssets(e.target.files)}
                />
              </div>
              <div className="asset-list">
                {assets.length === 0 && (
                  <div className="asset-empty">
                    Tus videos, imágenes y audios aparecerán aquí. Se guardan en el proyecto.
                  </div>
                )}
                {assets.map((a) => (
                  <div className="asset" key={a.id}>
                    <span>{a.type === "video" ? "🎬" : a.type === "image" ? "🖼️" : "🎵"}</span>
                    <div style={{ minWidth: 0 }}>
                      <strong>{a.name}</strong>
                      <small>
                        {peso(a.size)} · {a.type}
                      </small>
                    </div>
                  </div>
                ))}
              </div>
            </section>

            <section className="publish-card">
              <div>
                <p className="eyebrow">SIGUIENTE PASO</p>
                <h2>Publicar cuando estés listo</h2>
                <p>
                  {conectado
                    ? `Destino: ${cuentas.find((c) => c.id === cuentaSel)?.title ?? cuentas[0].title}`
                    : "Conectá tu cuenta de YouTube para publicar."}
                </p>
              </div>
              <button
                className="button primary"
                onClick={() => {
                  if (!video) return avisar("Cargá un video para continuar", true);
                  if (!conectado) {
                    avisar("Primero conectá tu cuenta de YouTube", true);
                    setVista("cuentas");
                    return;
                  }
                  setModal(true);
                }}
              >
                Preparar publicación →
              </button>
            </section>
          </>
        )}

        {vista === "proyectos" && (
          <div className="empty-state">
            Este es tu primer proyecto: <strong>{proyecto}</strong>
            <br />
            <span>La lista de proyectos se activa cuando conectemos la base de datos.</span>
          </div>
        )}

        {vista === "calendario" && (
          <div className="calendar-empty">
            Todavía no hay publicaciones programadas.
            <br />
            <span>Lo que confirmes desde el panel va a aparecer acá.</span>
          </div>
        )}

        {vista === "cuentas" && (
          <>
            <div className="section-heading" style={{ marginBottom: 14 }}>
              <div>
                <p className="eyebrow">CANAL DE DESTINO</p>
                <h2 style={{ margin: 0, fontSize: 19 }}>Tus canales de YouTube</h2>
              </div>
              <a className="button primary" href="/api/youtube/oauth/start">
                ＋ Conectar canal
              </a>
            </div>

            <div className="accounts-grid">
              {cuentas.map((c) => (
                <div className="account" key={c.id}>
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    className="netlogo avatar"
                    src={c.thumbnail || "https://i.ytimg.com/vi/placeholder/default.jpg"}
                    alt={c.title}
                  />
                  <div className="info">
                    <strong>{c.title}</strong>
                    <span>
                      {c.subscribers} subs · {c.videos} videos
                      {c.shared ? " · canal del servidor" : ""}
                    </span>
                  </div>
                  <button className="button danger" onClick={() => desconectar(c.id, c.title)}>
                    Desconectar
                  </button>
                </div>
              ))}

              {[
                ["Instagram", "ig", "◎"],
                ["TikTok", "tk", "♪"],
                ["Facebook", "fb", "f"],
              ].map(([nombre, clase, ico]) => (
                <div className="account" key={nombre}>
                  <b className={`netlogo ${clase}`}>{ico}</b>
                  <div className="info">
                    <strong>{nombre}</strong>
                    <span>Próximamente</span>
                  </div>
                  <button
                    className="button secondary"
                    onClick={() => avisar(`${nombre}: conector en la próxima fase`)}
                  >
                    Conectar
                  </button>
                </div>
              ))}
            </div>

            {!yt?.configured && (
              <div className="alert warn">
                Faltan las credenciales de Google. Copiá <code>.env.example</code> a{" "}
                <code>.env.local</code>, completá <code>YOUTUBE_CLIENT_ID</code> y{" "}
                <code>YOUTUBE_CLIENT_SECRET</code>, y reiniciá el servidor.
              </div>
            )}

            <div className="notice">
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap" }}>
                <strong>¿Cómo conecta cada usuario su cuenta?</strong>
                <button className="button ghost" onClick={() => setMostrarGuia((v) => !v)}>
                  {mostrarGuia ? "Ocultar guía" : "Ver guía"}
                </button>
              </div>

              {mostrarGuia && (
                <ol style={{ margin: "12px 0 0", paddingLeft: 20, lineHeight: 2 }}>
                  <li>
                    Entrá a <code>console.cloud.google.com</code> y creá un proyecto (o usá uno).
                  </li>
                  <li>
                    <em>APIs y servicios → Biblioteca</em>: habilitá <strong>YouTube Data API v3</strong>.
                  </li>
                  <li>
                    <em>Pantalla de consentimiento OAuth</em>: tipo <strong>Externo</strong>. Mientras la app
                    esté en modo <strong>Prueba</strong>, agregá a cada persona en{" "}
                    <strong>Usuarios de prueba</strong> (máximo 100).
                  </li>
                  <li>
                    <em>Credenciales → Crear credenciales → ID de cliente OAuth</em>: tipo{" "}
                    <strong>Aplicación de escritorio</strong> (permite localhost sin registrar cada puerto).
                  </li>
                  <li>
                    Pegá el <strong>Client ID</strong> y el <strong>Client Secret</strong> en{" "}
                    <code>web/.env.local</code> y reiniciá.
                  </li>
                  <li>
                    Cada usuario entra al panel y toca <strong>Conectar canal</strong>. Autoriza con su propia
                    cuenta de Google y vuelve solo.
                  </li>
                </ol>
              )}

              {yt?.redirectUri && (
                <div style={{ marginTop: 12 }}>
                  URI de redirección de este servidor:{" "}
                  <code style={{ color: "#c8d1e5", wordBreak: "break-all" }}>{yt.redirectUri}</code>
                </div>
              )}
            </div>

            <div className="notice">
              <strong>Privacidad:</strong> cada persona que entra al panel conecta su propia cuenta y
              solo ve sus canales. Los tokens quedan en el servidor (<code>web/data/accounts.json</code>) y
              nunca viajan al navegador. Al desconectar se borra el permiso guardado.
            </div>
          </>
        )}
      </main>

      {modal && (
        <div className="modal-backdrop" onClick={() => !subiendo && setModal(false)}>
          <div className="modal" onClick={(e) => e.stopPropagation()}>
            <h2>Publicar en YouTube</h2>
            <p style={{ color: "var(--muted)", fontSize: 12.5, margin: 0 }}>
              {video ? `${video.name} · ${peso(video.size)}` : "Sin video"}
            </p>

            <div className="field">
              <label>CANAL DE DESTINO</label>
              <select value={cuentaSel} onChange={(e) => setCuentaSel(e.target.value)}>
                {cuentas.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.title} ({c.subscribers} subs)
                  </option>
                ))}
              </select>
            </div>

            <div className="field">
              <label>TÍTULO</label>
              <input
                type="text"
                value={titulo}
                maxLength={100}
                onChange={(e) => setTitulo(e.target.value)}
                placeholder="Título del video"
              />
              <div className="hint">{titulo.length}/100 caracteres</div>
            </div>

            <div className="field">
              <label>DESCRIPCIÓN</label>
              <textarea
                value={descripcion}
                onChange={(e) => setDescripcion(e.target.value)}
                placeholder="Descripción, hashtags, créditos..."
              />
            </div>

            <div className="field row-2">
              <div>
                <label>TAGS (separados por coma)</label>
                <input type="text" value={tags} onChange={(e) => setTags(e.target.value)} />
              </div>
              <div>
                <label>VISIBILIDAD</label>
                <select
                  value={privacidad}
                  onChange={(e) => setPrivacidad(e.target.value as typeof privacidad)}
                >
                  <option value="public">Público</option>
                  <option value="unlisted">No listado</option>
                  <option value="private">Privado</option>
                </select>
              </div>
            </div>

            <div className="field">
              <label>MINIATURA (opcional)</label>
              <button className="button secondary" onClick={() => inputMini.current?.click()}>
                {miniatura ? miniatura.name : "Elegir imagen"}
              </button>
              <input
                ref={inputMini}
                type="file"
                accept="image/jpeg,image/png"
                hidden
                onChange={(e) => setMiniatura(e.target.files?.[0] ?? null)}
              />
              <div className="hint">JPG o PNG. Para Shorts, vertical 1080x1920.</div>
            </div>

            {error && <div className="alert err">{error}</div>}
            {resultado && (
              <div className="alert ok">
                Publicado en {resultado.channel}:{" "}
                <a href={resultado.url} target="_blank" rel="noreferrer">
                  {resultado.url}
                </a>
                {resultado.thumbnailWarning && (
                  <div style={{ marginTop: 6 }}>Miniatura: {resultado.thumbnailWarning}</div>
                )}
              </div>
            )}

            <div className="modal-actions">
              <button className="button ghost" onClick={() => setModal(false)} disabled={subiendo}>
                {resultado ? "Cerrar" : "Cancelar"}
              </button>
              <button className="button primary" onClick={publicar} disabled={subiendo || Boolean(resultado)}>
                {subiendo ? (
                  <>
                    <span className="spinner" />
                    Subiendo…
                  </>
                ) : (
                  "Publicar"
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {toast && <div className={`toast${toast.error ? " err" : ""}`}>{toast.texto}</div>}
    </div>
  );
}
