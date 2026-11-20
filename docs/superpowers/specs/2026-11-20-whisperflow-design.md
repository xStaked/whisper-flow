# WhisperFlow — diseño

Fecha: 2026-11-20
Estado: implementado (v0.1.0)

## Problema

Wispr Flow es de pago (~12 USD/mes) y manda el audio a la nube. Se quiere lo
mismo —mantener una tecla, hablar, y que el texto aparezca en la app activa—
pero gratis, offline y sin cuenta.

## Alcance del MVP

Dentro:

- Hotkey global: mantener `fn` para grabar, soltar para transcribir.
- Transcripción 100% local con `whisper.cpp`.
- Inserción del texto en la app enfocada.
- Panel flotante con los últimos textos y botón de copiar, como red de seguridad.
- Icono en la barra de menús con estado (listo / grabando / transcribiendo).

Fuera (a propósito):

- Reescritura con LLM, comandos de voz, puntuación configurable.
- Corrección de estilo, sinónimos, "flow" por app.
- Auto-update, notarización, App Store.
- Atajo configurable desde UI (se cambia en código si algún día hace falta).

## Decisiones

### 1. App nativa Swift, no script

Los permisos de macOS (micrófono, accesibilidad) se otorgan por identidad de
bundle. Un script de Python corrido desde Terminal queda atado a Terminal, y el
hotkey global se vuelve frágil. Un bundle real obtiene TCC limpio y arranca solo.

### 2. `whisper.cpp`, no Apple Speech

Calidad claramente mejor, multilingüe de verdad, y el modelo no depende de la
red ni de que Apple habilite on-device para tu locale. Costo: 547 MB de modelo.

Se compila desde el repo vendorizado con un cmake portable dentro del proyecto,
porque el entorno no permite escribir fuera del workspace ni instalar Homebrew.

### 3. `fn` como tecla

`fn` sola no genera caracteres, así que es la tecla ideal para push-to-talk. El
event tap la intercepta a nivel HID y **traga** los `flagsChanged` para que
macOS no abra el emoji picker. Cualquier otra tecla mientras `fn` está
presionada cancela la grabación, así `fn`+flechas y `fn`+F3 siguen funcionando.

### 4. Inserción en dos capas

1. Eventos Unicode (`CGEventKeyboardSetUnicodeString`) en trozos de 20 unidades
   UTF-16, sin tocar el portapapeles.
2. Verificación por Accessibility: se compara la posición del caret antes y
   después. Si no cambió, se reintenta con portapapeles + ⌘V y se restaura el
   portapapeles 0.6 s después.

Si ninguna capa se puede verificar, se abre el panel: el texto nunca se pierde.

### 5. Panel no activante

`NSPanel` con `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded`. Cuando aparece
porque la inserción falló, el foco se queda en la app donde estabas escribiendo;
si el panel activara la app, el texto iría al panel y se perdería el destino.

## Flujo de datos

```
CGEventTap (flagsChanged, fn)
  └─ onPress   → AudioRecorder.start()  → AVAudioEngine tap → [Float] en memoria
  └─ onRelease → AudioRecorder.stop()   → WAV 16-bit mono en temp
                    └─ Transcriber: ffmpeg -ar 16000 -ac 1 → whisper-cli → .txt
                         └─ clean() quita [BLANK_AUDIO], [MUSIC], etc.
                              └─ TranscriptStore.add()
                                   └─ TextInserter.insert() → éxito? → fin
                                                            → fallo  → panel.show()
  └─ onCancel  → AudioRecorder.cancel()
```

## Errores y estados

| Situación | Comportamiento |
|---|---|
| Sin permiso de micrófono | Alerta con botón a Ajustes. |
| Sin Accesibilidad | Alerta + reintento cada 2 s hasta que se conceda. |
| Audio vacío / < 0.3 s | No hace nada, vuelve a idle. |
| Whisper no entiende nada | Descarta el resultado (no inserta basura). |
| ffmpeg/whisper fallan | El panel se abre con el mensaje en rojo. |
| Inserción no verificable | Paneles abre con el texto para copiar. |
| Grabación > 120 s | Corta sola y transcribe. |

## Estructura

```
WhisperFlow/
├── Sources/            # 8 archivos Swift, uno por responsabilidad
├── Resources/Info.plist
├── build.sh            # compila + empaqueta + firma ad-hoc
├── download-model.sh
├── models/             # gitignored, 547 MB
└── vendor-whisper/     # gitignored, checkout de whisper.cpp
```

## Verificación hecha

- `say` → ffmpeg → `whisper-cli`: transcripción exacta en inglés y español.
- Latencia medida: 1.83 s (2.3 s de audio) y 1.93 s (9 s de audio) con idioma
  fijo; 3.34 s / 3.43 s con `auto`.
- La app arranca, resuelve rutas y escribe `config.json` correctamente.
- Pendiente de prueba manual: hotkey `fn` real, permisos TCC, inserción en apps
  de terceros (requiere interacción humana).

---

# Anexo: limpieza del texto con IA (v0.2.0)

## Objetivo

Wispr Flow no solo transcribe: pasa el texto por un LLM que quita muletillas,
arregla puntuación y separa oraciones. Se quería lo mismo, local.

## Hallazgo: Apple Intelligence no está disponible

`FoundationModels.framework` existe en macOS 26, pero al consultar
`SystemLanguageModel.default.availability` devuelve
`appleIntelligenceNotEnabled`: el modelo on-device está apagado y en la región
del usuario no está habilitado. El código quedó escrito y se usa solo si algún
día está disponible; no es el camino principal.

## Decisión: llama.cpp con modelo GGUF

- Binario precompilado oficial (`llama-b12589-bin-macos-arm64`), que **sí trae
  Metal** — a diferencia de whisper.cpp, que en esta máquina hubo que compilar
  sin GPU por falta del compilador de shaders.
- Modelo `Qwen2.5-3B-Instruct-Q4_K_M` (~1.8 GB): buen español, sigue
  instrucciones y conserva números/vocabulario técnico.
- Se invoca `llama-completion` (no `llama-cli`) con el template ChatML armado a
  mano: así stdout es solo la respuesta, sin banner ni bucle interactivo.
- `PostProcessor.sanitize` descarta la salida si difiere demasiado del original
  (menos de la mitad o más del doble de palabras), si viene vacía o si trae
  preámbulos tipo "Aquí está el texto limpio:". En ese caso gana el texto crudo.

## Por qué hay dos motores

Cargar 1.8 GB cuesta **~4.5 s** por dictado (medido: GPU 4.6 s, CPU 6.1 s, con
solo 0.3 s de diferencia entre cargar y generar). Eso es demasiado para el uso
normal, así que:

- **Reglas** (`RulesCleaner`): regex determinista, <10 ms, sin modelos. Quita
  `eh/um/mmm`, corrige espacios, mayúsculas y punto final. No reescribe.
- **IA local**: la limpieza real, opt-in, para dictados largos.

Se descartó mantener un `llama-server` residente: daría ~1 s por dictado pero
dejaría ~2.5 GB de RAM ocupados en reposo, justo lo contrario del diseño.

## Verificación

- `llama-completion` con template ChatML: quitó "pues"/"o sea", puso puntuación
  y separó oraciones sin alterar los números (29.5 / 13.5 / 18.5 / 40 / 60).
- `RulesCleaner`: "eh hola  eh  como estas ,  quiero..." → "Hola como estas,
  quiero...".
- La app arrancó tras recompilar con **los permisos intactos**, gracias a firmar
  con el certificado Apple Development en vez de ad-hoc.
