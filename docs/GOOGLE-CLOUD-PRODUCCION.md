# Google Cloud — cómo configurar la API para PRODUCCIÓN

> Guía para cuando el panel deje de ser local y lo use gente real.
> Complementa a `DESARROLLO.md`.

---

## 1. Lo que ya hay hoy (modo desarrollo)

- Proyecto en **Google Cloud Console** con **YouTube Data API v3** habilitada.
- Credencial **OAuth de tipo Aplicación de escritorio**.
- La pantalla de consentimiento está en **Prueba (Testing)**.
- El panel funciona en `http://localhost:3000`.

**En este modo:** solo pueden entrar las cuentas que estén en **Usuarios de prueba** (máx. 100)
y los tokens de refresco **caducan en 7 días** si la app sigue en Prueba y sin publicar.

---

## 2. Qué cambia en producción

| Tema | Desarrollo (hoy) | Producción |
|---|---|---|
| Pantalla de consentimiento | Prueba | **Publicada** |
| Usuarios | 100 de prueba | Cualquiera con cuenta Google |
| Refresh token | Caduca a los 7 días | Permanente (salvo revocación) |
| Tipo de cliente OAuth | Escritorio | **Aplicación web** con URIs registradas |
| Redirect URI | `http://localhost:3000/...` | `https://tu-dominio.com/api/youtube/oauth/callback` |
| HTTPS | No | **Obligatorio** |
| Cookie de sesión | `sameSite=lax` | `secure: true` además |

---

## 3. Paso a paso para publicar

### 3.1 Pantalla de consentimiento

1. **Google Cloud Console → APIs y servicios → Pantalla de consentimiento OAuth**
2. Tipo de usuario: **Externo** (si no es Google Workspace).
3. Completar:
   - Nombre de la app (lo que ve el usuario)
   - Correo de asistencia
   - Logo (120x120 px, opcional pero recomendado)
   - Dominios autorizados: `tu-dominio.com`
   - Enlaces: política de privacidad y términos **obligatorios**
   - Correo del desarrollador
4. **Scopes**: agregar
   - `https://www.googleapis.com/auth/youtube.upload`
   - `https://www.googleapis.com/auth/youtube.readonly`
5. **Guardar y continuar → Publicar app**.

### 3.2 Verificación (esto es lo que demora)

`youtube.upload` es un **scope sensible**. Google va a pedir:

- **Video de demostración** (2-3 min) mostrando el flujo completo:
  inicio de sesión → conectar canal → elegir video → publicar → ver el video en YouTube.
- Justificación escrita de por qué se necesita subir videos.
- Explicación de cómo se usan los datos y cómo se borran.
- Política de privacidad publicada en el dominio.

**Mientras no esté verificado**, Google puede limitar los videos subidos por API a
**privado** aunque se pida `public`. Hay que revisar el estado del proyecto en la consola.

> Si el caso de uso es "un creador sube a su propio canal", normalmente alcanza con la
> verificación de scopes. Si se opera en nombre de terceros, se necesita además la
> **verificación de marca (Brand Verification)**.

### 3.3 Credencial de producción

1. **Credenciales → Crear credenciales → ID de cliente OAuth**
2. Tipo: **Aplicación web**
3. **URIs de redirección autorizados**:
   ```
   https://tu-dominio.com/api/youtube/oauth/callback
   ```
   (podés dejar también la de localhost para seguir probando)
4. **Orígenes autorizados de JavaScript**: `https://tu-dominio.com`
5. Copiar `Client ID` y `Client Secret` al `.env.local` / variables del hosting.

### 3.4 Variables en producción

```ini
APP_URL=https://tu-dominio.com
YOUTUBE_CLIENT_ID=...
YOUTUBE_CLIENT_SECRET=...
YOUTUBE_REDIRECT_URI=https://tu-dominio.com/api/youtube/oauth/callback
OPENROUTER_KEY=...
DEEPSEEK_MODELO=deepseek/deepseek-v4.1-flash-1017
GOOGLE_AI_KEY=...
```

Y ajustar la cookie en `web/lib/session.ts`:

```ts
store.set(SESSION_COOKIE, nuevo, {
  httpOnly: true,
  sameSite: "lax",
  path: "/",
  secure: true,        // ← solo en HTTPS
  maxAge: UN_ANIO,
});
```

---

## 4. Cuotas y límites reales de YouTube

| Concepto | Valor | Impacto |
|---|---|---|
| Cuota diaria por proyecto | **10.000 unidades** | Se reinicia a medianoche del Pacífico |
| `videos.insert` (subir) | **1.600 unidades** | ≈ **6 videos por día** |
| `thumbnails.set` | 50 unidades | Poco relevante |
| `channels.list` | 1 unidad | Se puede consultar seguido |
| Límite de subidas por día por cuenta | ~100 (varía) | No se llega con la cuota |

**Qué hacer si se necesita más:** pedir aumento de cuota desde
*APIs y servicios → YouTube Data API v3 → Cuotas*, explicando el caso de uso.
Google suele tardar días y puede pedir lo mismo que la verificación.

**Mitigación en el panel:** mostrar las subidas restantes del día y avisar cuando queden menos de 2.

---

## 5. Seguridad de los tokens

| Práctica | Cómo |
|---|---|
| Nunca en el navegador | Los tokens viven solo en el servidor (`web/data/`) |
| Cifrado en reposo | Hoy no; en producción usar DB con cifrado (Vault, KMS o `crypto` + clave en env) |
| Rotación | Si se filtra un `refresh_token`, se revoca desde `myaccount.google.com/permissions` |
| Revocación | `POST https://oauth2.googleapis.com/revoke?token=<token>` — conviene al "Desconectar" |
| Registro | Guardar qué usuario conectó qué canal y cuándo |
| Alcance mínimo | Pedir solo `youtube.upload` + `youtube.readonly` |

### Mejora pendiente: revocar de verdad

Hoy "Desconectar" borra el token de nuestra base. Lo correcto es **además** llamar a:

```http
POST https://oauth2.googleapis.com/revoke
Content-Type: application/x-www-form-urlencoded

token=<refresh_token>
```

Así el usuario ve el permiso eliminado también en su cuenta de Google.

---

## 6. Checklist antes de abrir el panel al público

- [ ] Dominio con HTTPS y certificado válido
- [ ] Pantalla de consentimiento **publicada**
- [ ] Scopes sensibles **verificados** (o proyecto en producción con límites asumidos)
- [ ] Redirect URI de producción registrada en la credencial web
- [ ] `YOUTUBE_REDIRECT_URI` apuntando al dominio real
- [ ] Cookie con `secure: true`
- [ ] Login de usuarios (hoy no existe: cualquiera con la URL crea sesión)
- [ ] Base de datos real en vez de `data/*.json`
- [ ] Cifrado de tokens
- [ ] Revocación real al desconectar
- [ ] Política de privacidad y términos publicados
- [ ] Video de demostración para la verificación de Google
- [ ] Aviso de cuota diaria en la UI
- [ ] Logs de auditoría (quién publicó qué y cuándo)

---

## 7. Diferencias con los otros canales del usuario

El repo de Furia ya tiene su propia credencial y su token guardado como archivo.
**No se mezclan**: el panel gestiona sus canales por sesión desde `web/data/accounts.json`.
El token viejo de Furia se migró como cuenta **compartida del servidor** solo para no perderlo;
en producción conviene desconectarla y que cada usuario conecte la suya.
