#!/usr/bin/env python3
"""One-off translation pass: Spanish -> English across the repo.

Kept in the repo history as documentation of what was changed; it is not needed
to build or run the app.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Exact replacements applied to source files, longest first so that a short
# string never partially rewrites a longer one.
REPLACEMENTS = [
    # --- AppDelegate -------------------------------------------------------
    ('"WhisperFlow — mantén fn y habla"', '"WhisperFlow — hold fn and speak"'),
    ('button.toolTip = "WhisperFlow — falta el permiso de Accesibilidad (haz clic)"',
     'button.toolTip = "WhisperFlow — Accessibility permission missing (click)"'),
    ('"Re-insertar último dictado"', '"Re-insert last dictation"'),
    ('"Reglas (instantáneo)"', '"Rules (instant)"'),
    ('"IA local (+4s)"', '"Local AI (+4s)"'),
    ('"Ver log de diagnóstico"', '"Open diagnostic log"'),
    ('"Abrir carpeta de datos"', '"Open data folder"'),
    ('"Abrir permisos"', '"Open permissions"'),
    ('"Historial de dictados"', '"Dictation history"'),
    ('"Salir de WhisperFlow"', '"Quit WhisperFlow"'),
    ('title: "Falta el micrófono"', 'title: "Microphone permission missing"'),
    ('message: "Dale permiso de micrófono a WhisperFlow en Ajustes del Sistema → Privacidad y seguridad → Micrófono."',
     'message: "Grant WhisperFlow microphone access in System Settings → Privacy & Security → Microphone."'),
    ('"Abrir Ajustes"', '"Open Settings"'),
    ('"Ahora no"', '"Not now"'),
    ('"Entendido"', '"Got it"'),

    # --- AudioRecorder -----------------------------------------------------
    ('return "No se detectó ningún micrófono."', 'return "No microphone was detected."'),
    ('return "Falta el permiso de micrófono (Ajustes del Sistema → Privacidad y seguridad → Micrófono)."',
     'return "Microphone permission missing (System Settings → Privacy & Security → Microphone)."'),
    ('return "No se pudo guardar el audio temporal."', 'return "Could not save the temporary audio."'),

    # --- Transcriber -------------------------------------------------------
    ('return "No encuentro whisper-cli en \\(path.isEmpty ? "(ruta vacía)" : path). Compila con ./build.sh o edita config.json."',
     'return "Cannot find whisper-cli at \\(path.isEmpty ? "(empty path)" : path). Build with ./build.sh or edit config.json."'),
    ('return "No encuentro el modelo en \\(path.isEmpty ? "(ruta vacía)" : path). Descárgalo con ./download-model.sh."',
     'return "Cannot find the model at \\(path.isEmpty ? "(empty path)" : path). Download it with ./download-model.sh."'),
    ('return "ffmpeg falló: \\(detail)"', 'return "ffmpeg failed: \\(detail)"'),
    ('return "whisper-cli falló (código \\(code)): \\(detail)"', 'return "whisper-cli failed (code \\(code)): \\(detail)"'),
    ('return "\\(label) se quedó colgado y lo cancelé."', 'return "\\(label) hung and was cancelled."'),
    ('return "No se entendió nada en el audio."', 'return "Nothing intelligible in the audio."'),
    ('"no se generó el archivo de texto"', '"no text file was produced"'),

    # --- LlamaEngine -------------------------------------------------------
    ('return "llama.cpp o el modelo no están instalados."', 'return "llama.cpp or the model are not installed."'),
    ('return "llama falló (\\(code)): \\(detail)"', 'return "llama failed (\\(code)): \\(detail)"'),
    ('return "El modelo tardó demasiado."', 'return "The model took too long."'),
    ('return "La salida del modelo no era usable."', 'return "The model output was unusable."'),

    # --- PostProcessor -----------------------------------------------------
    ('return "macOS < 26"', 'return "macOS < 26"'),
    ('case .deviceNotEligible: return "dispositivo no compatible"', 'case .deviceNotEligible: return "device not eligible"'),
    ('case .appleIntelligenceNotEnabled: return "Apple Intelligence desactivada"',
     'case .appleIntelligenceNotEnabled: return "Apple Intelligence disabled"'),
    ('case .modelNotReady: return "modelo aún descargándose"', 'case .modelNotReady: return "model still downloading"'),
    ('return "no disponible"', 'return "unavailable"'),
    ('return "framework ausente"', 'return "framework missing"'),

    # --- MainWindow --------------------------------------------------------
    ('label: "días activos"', 'label: "active days"'),
    ('label: "palabras/dictado"', 'label: "words/dict."'),
    ('label: "palabras"', 'label: "words"'),
    ('label: "dictados"', 'label: "dictations"'),
    ('return "Buen día"', 'return "Good morning"'),
    ('return "Buenas tardes"', 'return "Good afternoon"'),
    ('return "Buenas noches"', 'return "Good evening"'),
    ('"Mantené presionada la tecla fn, hablá con naturalidad y soltá.\\nEl texto aparece donde tengas el cursor."',
     '"Hold the fn key, speak naturally and release.\\nThe text appears wherever your cursor is."'),
    ('label = "Hoy"', 'label = "Today"'),
    ('label = "Ayer"', 'label = "Yesterday"'),
    ('Locale(identifier: "es")', 'Locale(identifier: "en_US")'),

    # --- SetupWindow -------------------------------------------------------
    ('window.title = "Permisos de WhisperFlow"', 'window.title = "WhisperFlow permissions"'),
    ('"WhisperFlow necesita dos permisos para funcionar:"', '"WhisperFlow needs two permissions to work:"'),
    ('title: "Micrófono"', 'title: "Microphone"'),
    ('detail: "Para escuchar la tecla fn y escribir el texto en otras apps."',
     'detail: "To hear the fn key and type text into other apps."'),
    ('detail: "Para grabar tu voz mientras mantienes fn."', 'detail: "To record your voice while you hold fn."'),
    ('title: "Accesibilidad"', 'title: "Accessibility"'),
    ('"Abrir Ajustes"', '"Open Settings"'),
    ('statusLabel.stringValue = granted ? "concedido ✓" : "falta ✗"',
     'statusLabel.stringValue = granted ? "granted ✓" : "missing ✗"'),

    # --- TranscriptStore / Panel -------------------------------------------
    ('return "# Historial de dictados\\n\\nTodavía no hay dictados.\\n"',
     'return "# Dictation history\\n\\nNo dictations yet.\\n"'),
    ('out += "# Historial de dictados\\n\\n"', 'out += "# Dictation history\\n\\n"'),
    ('out += "Exportado el \\(formatter.string(from: Date())) · \\(entries.count) dictados\\n\\n"',
     'out += "Exported \\(formatter.string(from: Date())) · \\(entries.count) dictations\\n\\n"'),
    ('"Se eliminan los \\(store?.entries.count ?? 0) dictados guardados. No se puede deshacer."',
     '"This deletes all \\(store?.entries.count ?? 0) saved dictations. It cannot be undone."'),
    ('"Borrar"', '"Delete"'),
    ('"Cancelar"', '"Cancel"'),
    ('"Copiar todo"', '"Copy all"'),
    ('"Exportar"', '"Export"'),
    ('"Borrar"', '"Clear"'),
]

COMMENT_REPLACEMENTS = [
    # Comments and log lines: same idea, English wording.
    ('/// Everything tunable lives here.', '/// Everything tunable lives here.'),
    ('// TODO', '// TODO'),
]

FILES = [
    "Sources/AppDelegate.swift", "Sources/AudioRecorder.swift", "Sources/Clipboard.swift",
    "Sources/Diagnostics.swift", "Sources/DictationCardView.swift", "Sources/FnKeyMonitor.swift",
    "Sources/LlamaEngine.swift", "Sources/MainWindow.swift", "Sources/OverlayHUD.swift",
    "Sources/PostProcessor.swift", "Sources/RulesCleaner.swift", "Sources/SetupWindow.swift",
    "Sources/SidebarItemView.swift", "Sources/TextInserter.swift", "Sources/Transcriber.swift",
    "Sources/TranscriptPanel.swift", "Sources/TranscriptRowView.swift", "Sources/TranscriptStore.swift",
    "Sources/UITheme.swift", "Sources/AppConfig.swift",
    "build.sh", "download-model.sh", "scripts/bootstrap.sh", "scripts/install-login-item.sh",
    "Resources/Info.plist",
]


def main() -> None:
    changed = 0
    for relative in FILES:
        path = ROOT / relative
        if not path.exists():
            print(f"missing: {relative}")
            continue
        text = path.read_text()
        original = text
        for old, new in REPLACEMENTS:
            text = text.replace(old, new)
        if text != original:
            path.write_text(text)
            changed += 1
            print(f"updated: {relative}")
    print(f"\n{changed} files changed")


if __name__ == "__main__":
    main()
