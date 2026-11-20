# WhisperFlow

Dictado por voz, **gratis y 100% local**, para macOS. Mantienes la tecla `fn`,
hablas, sueltas — y el texto aparece en la app donde tengas el cursor.

Es un clon minimalista de Wispr Flow sin suscripción: el audio nunca sale de tu
Mac, no hay cuenta, no hay nube.

```
mantén fn ──► graba ──► whisper.cpp local ──► [limpieza opcional] ──► escribe el texto
                                                              └──► panel (si falla)
```

## Qué hay aquí

| Archivo | Qué hace |
|---|---|
| `Sources/FnKeyMonitor.swift` | Escucha `fn` con un event tap de bajo nivel y lo traga para que macOS no abra el emoji picker. Otra tecla mientras `fn` está presionada = cancela. |
| `Sources/AudioRecorder.swift` | `AVAudioEngine` (uno nuevo por grabación) → samples en memoria → WAV 16-bit mono. |
| `Sources/Transcriber.swift` | `ffmpeg` a 16 kHz + `whisper-cli` + limpieza de alucinaciones. Timeouts duros. |
| `Sources/TextInserter.swift` | Escribe al cursor tipeando eventos Unicode (sin tocar el portapapeles); si el destino los ignora, cae a ⌘V. |
| `Sources/RulesCleaner.swift` | Limpieza instantánea: quita muletillas, arregla espacios, mayúsculas y punto final. |
| `Sources/LlamaEngine.swift` | Limpieza con LLM local (llama.cpp + Metal). |
| `Sources/PostProcessor.swift` | Cadena de limpieza: Apple Intelligence → llama.cpp → texto crudo, con salvaguardas. |
| `Sources/TranscriptPanel.swift` | Panel flotante que no roba el foco, con los últimos 20 textos y botón "Copiar último". |
| `Sources/TranscriptStore.swift` | Historial persistente en JSON (50 entradas). |
| `Sources/Diagnostics.swift` | Log en `~/Library/Application Support/WhisperFlow/whisperflow.log`. |
| `Sources/AppDelegate.swift` | Icono de barra de menús, estados, permisos, menú. |

## Requisitos

- macOS 13+ (probado en macOS 26 / Apple Silicon)
- `ffmpeg` en el PATH (o edita `ffmpegPath` en el config)
- `whisper-cli` compilado en `vendor-whisper/` (o el que trae el bundle)

## Compilar

```bash
./build.sh
open build/WhisperFlow.app
```

`build.sh` compila el bundle Swift, copia `whisper-cli` dentro de la app y la firma
con tu certificado **Apple Development** si existe (así los permisos de macOS
sobreviven a cada recompilación). Si no hay certificado, firma ad-hoc y macOS
pedirá los permisos otra vez tras cada build.

Modelos:

```bash
./download-model.sh                                        # voz, ~547 MB
curl -L -o models/Qwen2.5-3B-Instruct-Q4_K_M.gguf \
  https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf   # limpieza IA, ~1.8 GB
```

## Permisos (una sola vez)

1. **Micrófono** → permitir.
2. **Accesibilidad** (Ajustes → Privacidad y seguridad → Accesibilidad) → activar
   *WhisperFlow*. Sin esto no puede escuchar `fn` ni escribir texto.

Si al mantener `fn` se abre el selector de emojis:
**Ajustes → Teclado → "Presionar 🌐 para" → No hacer nada**.

La app trae una ventana de permisos que se actualiza en vivo y se cierra sola
cuando ambos están concedidos.

## Uso

- **Mantén `fn`** y habla. Al soltar, transcribe y escribe.
- **Clic** en el icono → panel con lo último dictado.
- **Clic derecho** → menú: limpieza del texto, permisos, log, configuración, salir.

Icono: micrófono = listo · rojo = grabando · naranja = transcribiendo.

## Indicador en pantalla

Mientras dictás aparece una píldora abajo al centro (100 px sobre el Dock):

```
╭──────────────────────────╮
│ 🎙  ▁▃▅▇▅▃▁▂▄▆▄▂   0:07  │   grabando
╰──────────────────────────╯
```

- **El waveform es tu voz real**, no una animación decorativa: mide RMS en dBFS
  con ganancia adaptativa, así que responde igual con AirPods, con el micro interno
  o con un USB, y no hace falta gritar para que se mueva.
- **Cronómetro**, útil en dictados largos y para saber cuánto falta al corte de 120 s.
- Al soltar cambia a `transcribiendo…`, después `✓ insertado` (o `revisá el panel`)
  y desaparece solo.
- Es **click-through y no activante**: los clics lo atraviesan y nunca roba el foco,
  así el texto siempre cae en la app correcta. Funciona en fullscreen y en todos los Spaces.
- Se apaga en **clic derecho → Indicador en pantalla** (o `showOverlay: false`).

## Limpieza del texto (opcional)

Clic derecho → **Limpieza del texto**:

| Modo | Latencia | Qué hace |
|---|---|---|
| Desactivada | 0 | Texto crudo de Whisper (ya trae puntuación). |
| **Reglas** | ~0 ms | Quita `eh/um/mmm`, arregla espacios y mayúsculas, punto final. Nunca cambia el sentido. |
| **IA local** | +4-5 s | LLM local: reescribe puntuación, quita `pues` y `o sea`, separa oraciones. Conserva números y vocabulario técnico. |

La IA no corre en dictados de menos de `postProcessMinWords` palabras (12 por
defecto): en comandos cortos la latencia pesa más que la limpieza.

Probado con `Qwen2.5-3B-Instruct-Q4_K_M`. Para cambiarlo, apunta `llmModelPath`
a otro `.gguf` y reinicia.

> **Por qué no Apple Intelligence:** en macOS 26 el framework
> `FoundationModels` existe, pero en esta máquina el modelo on-device está
> desactivado (`appleIntelligenceNotEnabled`) y en la región no está disponible.
> El código lo intenta primero y, si está, lo usa (es más rápido que llama.cpp).
> Si no, cae a llama.cpp.

## Configuración

`~/Library/Application Support/WhisperFlow/config.json`

| Clave | Default | Notas |
|---|---|---|
| `language` | `"es"` | `"es"`, `"en"` o `"auto"`. `auto` cuesta ~1.5 s extra. |
| `modelPath` | `models/ggml-large-v3-turbo-q5_0.bin` | Voz. |
| `postProcess` | `false` | Interruptor de limpieza (el menú lo cambia en vivo). |
| `postProcessEngine` | `"rules"` | `"rules"` o `"llm"`. |
| `postProcessMinWords` | `12` | Mínimo de palabras para aplicar IA. |
| `showOverlay` | `true` | Indicador flotante en pantalla. |
| `llmModelPath` | `models/Qwen2.5-3B-Instruct-Q4_K_M.gguf` | Modelo de limpieza. |
| `llmBinaryPath` | `vendor-llama/*/llama-completion` | Runtime de llama.cpp. |
| `maxRecordSeconds` | `120` | Corta sola si te olvidas soltar. |
| `soundsEnabled` | `true` | Tink al empezar, Pop al terminar. |
| `autoInsert` | `true` | Si es `false`, solo llena el panel. |

## Rendimiento medido (M4 Pro)

| Etapa | Memoria | Tiempo |
|---|---|---|
| App en reposo | 21 MB | ~0% CPU |
| Transcripción (`whisper-cli`) | pico 832 MB, luego libera | 2 s (audio 23 s) · 7 s (audio 46 s) |
| Limpieza "reglas" | despreciable | <10 ms |
| Limpieza "IA local" | pico ~2.5 GB, luego libera | ~4.5 s |

El modelo de voz no queda residente: se carga y se libera en cada dictado. Esa es
la razón de que en reposo sean 21 MB en vez de 900 MB.

## Cuándo no funciona la inserción automática

- Campos con **secure input** (contraseñas, algunos bancos) — macOS lo bloquea.
- Apps Electron/web que ignoran eventos Unicode → el fallback ⌘V lo cubre.
- Si tampoco así entra, el texto queda **copiado al portapapeles** y la píldora
  avisa `copiado al portapapeles` con un icono teal. No abre ninguna ventana: una
  ventana emergente activaría WhisperFlow y el siguiente dictado caería dentro de
  ella en vez de en tu app.

## Desarrollo

El hotkey vive en un `CGEventTap` de bajo nivel. Regla de oro: **nunca hacer
trabajo pesado dentro del callback** — si tarda más de ~1 s, macOS deshabilita el
tap (`tapDisabledByTimeout`) y el atajo muere hasta reiniciar. Por eso todo se
despacha a la cola principal y hay un watchdog que reinstala el tap cada 15 s.

```bash
./build.sh                    # compila y firma
open build/WhisperFlow.app    # corre
tail -f ~/Library/Application\ Support/WhisperFlow/whisperflow.log   # diagnóstico
```

## Desinstalar

```bash
rm -rf ~/Library/Application\ Support/WhisperFlow
rm -rf build/WhisperFlow.app
```

Y quita el permiso de Accesibilidad en Ajustes.
