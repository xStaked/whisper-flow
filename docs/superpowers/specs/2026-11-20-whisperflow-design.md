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
