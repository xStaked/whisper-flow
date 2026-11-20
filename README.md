# WhisperFlow

Dictado por voz, **gratis y 100% local**, para macOS. Mantienes la tecla `fn`,
hablas, sueltas — y el texto aparece en la app donde tengas el cursor.

Es un clon minimalista de Wispr Flow sin suscripción: el audio nunca sale de tu
Mac, no hay cuenta, no hay nube.

```
mantén fn ──► graba ──► whisper.cpp local ──► escribe el texto ──► panel (por si falla)
```

## Qué hay aquí

| Archivo | Qué hace |
|---|---|
| `Sources/FnKeyMonitor.swift` | Escucha `fn` con un event tap de bajo nivel y lo traga para que macOS no abra el emoji picker. Otra tecla mientras `fn` está presionada = cancela. |
| `Sources/AudioRecorder.swift` | `AVAudioEngine` → samples en memoria → WAV 16-bit mono. |
| `Sources/Transcriber.swift` | `ffmpeg` a 16 kHz + `whisper-cli` + limpieza de alucinaciones. |
| `Sources/TextInserter.swift` | Escribe al cursor con eventos Unicode; si no se puede verificar, cae a portapapeles + ⌘V. |
| `Sources/TranscriptPanel.swift` | Panel flotante que no roba el foco, con los últimos 20 textos seleccionables y botón "Copiar último". |
| `Sources/TranscriptStore.swift` | Historial persistente en JSON (50 entradas). |
| `Sources/AppDelegate.swift` | Icono de barra de menús, estados, permisos, menú. |

## Requisitos

- macOS 13+ (probado en macOS 26 / Apple Silicon)
- `ffmpeg` en el PATH (o edita `ffmpegPath` en el config)
- Los binarios ya compilados de este repo: `vendor-whisper/build/bin/whisper-cli`

## Compilar

```bash
./build.sh
open build/WhisperFlow.app
```

`build.sh` compila el bundle Swift, copia `whisper-cli` dentro de la app y firma
ad-hoc. El modelo se busca en `models/`; si te falta:

```bash
./download-model.sh            # large-v3-turbo q5_0, ~547 MB
```

## Permisos (una sola vez)

Al abrirla por primera vez macOS pide dos cosas:

1. **Micrófono** → permitir.
2. **Accesibilidad** (Ajustes → Privacidad y seguridad → Accesibilidad) → activar
   *WhisperFlow*. Sin esto no puede escuchar `fn` ni escribir texto.

Si al mantener `fn` se abre el selector de emojis, desactívalo una vez:
**Ajustes → Teclado → "Presionar 🌐 para" → No hacer nada**.

## Uso

- **Mantén `fn`** y habla. Al soltar, transcribe y escribe.
- **Clic** en el icono del micrófono → panel con lo último dictado.
- **Clic derecho** → menú (permisos, configuración, salir).

Icono: micrófono normal = listo · rojo = grabando · naranja = transcribiendo.

## Configuración

`~/Library/Application Support/WhisperFlow/config.json`

| Clave | Default | Notas |
|---|---|---|
| `language` | `"es"` | `"es"`, `"en"`, o `"auto"`. `auto` detecta pero cuesta ~1.5 s extra. |
| `modelPath` | `models/ggml-large-v3-turbo-q5_0.bin` | Cambia a `ggml-small.bin` para ir más rápido. |
| `whisperBinaryPath` | dentro del bundle | |
| `ffmpegPath` | `/opt/homebrew/bin/ffmpeg` | |
| `maxRecordSeconds` | `120` | Corta sola si te olvidas soltar. |
| `soundsEnabled` | `true` | Tink al empezar, Pop al terminar. |
| `autoInsert` | `true` | Si lo pones en `false`, solo llena el panel para copiar. |

Reinicia la app después de editar el config.

## Rendimiento medido (M4 Pro, CPU + Accelerate)

| Audio | `language: "es"` / `"en"` | `"auto"` |
|---|---|---|
| 2.3 s | 1.83 s | 3.34 s |
| 9 s | 1.93 s | 3.43 s |

Es casi constante porque whisper siempre procesa una ventana de 30 s.

## Cuándo no funciona la inserción automática

- Campos con **secure input** (contraseñas, algunos bancos) — macOS lo bloquea a propósito.
- Algunas apps Electron/web ignoran eventos Unicode → el fallback ⌘V lo cubre.
- Si tampoco así entra, el panel se abre solo con el texto listo para copiar.

## Desinstalar

```bash
rm -rf ~/Library/Application\ Support/WhisperFlow
rm -rf build/WhisperFlow.app
```

Y quita el permiso de Accesibilidad en Ajustes.
