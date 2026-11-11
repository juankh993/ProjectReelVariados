# Música de fondo

Esta carpeta no se versiona (los audios pesan). Dejá acá 2 o 3 temas y usalos rotando
para que los videos no suenen todos igual.

## De dónde bajarla (gratis y con licencia)

| Fuente | Licencia | Cómo |
|---|---|---|
| **YouTube Audio Library** | Uso libre en YouTube (algunas piden crédito) | studio.youtube.com → **Audio Library**, filtrar "Sin atribución" |
| **Pixabay Music** | Pixabay License | pixabay.com/music → descargar MP3 |
| **Free Music Archive** | Revisar cada tema (CC0 / CC BY) | freemusicarchive.org |

> Regla del canal: nada de música de TikTok, Instagram ni de otros videos. Si el tema
> es CC BY, el crédito va en la descripción y se anota en `docs/LICENCIAS.md`.

### YouTube Audio Library, paso a paso

1. Entrá a **studio.youtube.com** con la cuenta de Datoneta.
2. Menú izquierdo → **Audio Library**.
3. Filtrá por **"Sin atribución"** (o anotá los que pidan crédito).
4. Escuchá y descargá 2 o 3 temas **instrumentales, sin voz y sin batería marcada**.
5. Renombralos `tema-01.mp3`, `tema-02.mp3`, `tema-03.mp3` y dejarlos en esta carpeta.
6. Anotá autor/tema en `docs/LICENCIAS.md` (aunque no pida crédito).

> Los temas de YouTube Audio Library están liberados **para YouTube**. Si algún día
> se sube el mismo video a TikTok o Instagram, usar Pixabay Music para esa copia.

## Cómo usarla en el reel

```json
"musica": { "archivo": "05-musica/tema-suave.mp3", "vol": 0.12 }
```

- Se repite en loop y se corta a la duración del video.
- `vol` 0.14-0.16: tiene que estar por debajo de la voz, pero que se escuche.
- Buscar temas **sin batería marcada ni voz**: el dato tiene que quedar claro.
- Si el tema sube mucho en el estribillo, mejor otro: el volumen del fondo tiene que
  ser parejo de punta a punta.

## Nombres sugeridos

`tema-01.mp3`, `tema-02.mp3`, `tema-03.mp3` — y anotá en `docs/LICENCIAS.md` de dónde
salió cada uno.
