#!/usr/bin/env python3
"""Second pass: translate log lines and code comments to English."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent

REPL = [
    # ---------------- AppDelegate ----------------
    ('"--- WhisperFlow arrancó ---"', '"--- WhisperFlow started ---"'),
    ('"micrófono: \\(AudioRecorder.permissionStatusDescription)"', '"microphone: \\(AudioRecorder.permissionStatusDescription)"'),
    ('"arranque: quedé activa sin ventanas, cediendo el foco"', '"startup: active with no windows, yielding focus"'),
    ('// La píldora no puede quedarse animando si no hay grabación real.',
     '// The pill must never keep animating when there is no real recording.'),
    ('"salud: píldora grabando sin grabación, se oculta"', '"health: pill recording without a recording, hiding"'),
    ('"reinsertar: \\(inserted ? "verificada" : "falló")"', '"reinsert: \\(inserted ? "verified" : "failed")"'),
    ('"onPress: sin permiso de micrófono"', '"onPress: no microphone permission"'),
    ('"grabación: primer intento falló (\\(error.localizedDescription)), reintentando"',
     '"recording: first attempt failed (\\(error.localizedDescription)), retrying"'),
    ('"grabación: error \\(error.localizedDescription)"', '"recording: error \\(error.localizedDescription)"'),
    ('"grabación: fn se soltó durante el arranque, se descarta"', '"recording: fn released during startup, discarding"'),
    ('"grabación: fn se soltó durante el arranque, se cierra ya"', '"recording: fn released during startup, closing now"'),
    ('"grabación: empezó"', '"recording: started"'),
    ('"onRelease: el arranque seguía en curso, se cerrará al terminar"',
     '"onRelease: startup still in flight, will close when it finishes"'),
    ('"onRelease: no había grabación activa"', '"onRelease: no active recording"'),
    ('"onRelease: el audio quedó vacío"', '"onRelease: captured audio was empty"'),
    ('"grabación: terminó (\\(String(format: "%.1f", capture.durationSeconds))s), transcribiendo"',
     '"recording: finished (\\(String(format: "%.1f", capture.durationSeconds))s), transcribing"'),
    ('"transcripción: error \\(error.localizedDescription)"', '"transcription: error \\(error.localizedDescription)"'),
    ('"onCancel: el arranque seguía en curso, se descartará"', '"onCancel: startup still in flight, will discard"'),
    ('"inserción: \\(inserted ? "verificada" : "NO verificada")"', '"insertion: \\(inserted ? "verified" : "NOT verified")"'),
    ('"inserción: desactivada (autoInsert=false)"', '"insertion: disabled (autoInsert=false)"'),
    ('"inserción fallida: texto copiado al portapapeles"', '"insertion failed: text copied to the clipboard"'),
    ('"config: limpieza = \\(enabled ? engine : "off")"', '"config: cleanup = \\(enabled ? engine : "off")"'),
    ('"config: overlay = \\(config.showOverlay)"', '"config: overlay = \\(config.showOverlay)"'),
    ('"historial: \\(store.fileURL.path)"', '"history: \\(store.fileURL.path)"'),
    ('"idioma: \\(config.language)"', '"language: \\(config.language)"'),
    ('"texto: \\(text)"', '"text: \\(text)"'),
    ('"clic: falta accesibilidad, abriendo ajustes"', '"click: accessibility missing, opening settings"'),
    ('"permisos: ambos concedidos"', '"permissions: both granted"'),
    ('"permisos: abriendo \\(raw)"', '"permissions: opening \\(raw)"'),
    ('"prueba: insertando texto de diagnóstico"', '"probe: inserting diagnostic text"'),
    ('"prueba: resultado = \\(ok ? "OK" : "FALLÓ")"', '"probe: result = \\(ok ? "OK" : "FAILED")"'),

    # ---------------- AudioRecorder ----------------
    ('"audio: reconfiguración de arranque ignorada (\\(String(format: "%.2f", age))s)"',
     '"audio: startup reconfiguration ignored (\\(String(format: "%.2f", age))s)"'),
    ('"audio: cambió el dispositivo a mitad de grabación, cerrando"',
     '"audio: device changed mid-recording, closing"'),
    ('"audio: límite de \\(Int(maxSeconds))s alcanzado"', '"audio: \\(Int(maxSeconds))s limit reached"'),
    ('"audio: el dispositivo no reporta formato válido"', '"audio: device reports no valid format"'),
    ('"audio: tap reinstalado a \\(Int(format.sampleRate)) Hz"', '"audio: tap reinstalled at \\(Int(format.sampleRate)) Hz"'),
    ('"audio: no llegaron muestras, reinstalando el tap"', '"audio: no samples arrived, reinstalling the tap"'),
    ('"audio: no se pudo reanudar — \\(error.localizedDescription)"', '"audio: could not resume — \\(error.localizedDescription)"'),
    ('"audio: \\(Int(format.sampleRate)) Hz · \\(format.channelCount) canal(es)"',
     '"audio: \\(Int(format.sampleRate)) Hz · \\(format.channelCount) channel(s)"'),

    # ---------------- Clipboard ----------------
    ('"portapapeles: copiado (\\(text.count) caracteres)"', '"clipboard: copied (\\(text.count) characters)"'),
    ('"portapapeles: no se restaura, hubo una copia nueva"', '"clipboard: not restoring, a newer copy happened"'),
    ('"portapapeles: restaurado el contenido anterior"', '"clipboard: previous content restored"'),

    # ---------------- FnKeyMonitor ----------------
    ('"tap: NO instalado (sin permiso de accesibilidad)"', '"tap: NOT installed (no Accessibility permission)"'),
    ('"tap: CGEvent.tapCreate devolvió nil"', '"tap: CGEvent.tapCreate returned nil"'),
    ('"tap: instalado correctamente"', '"tap: installed successfully"'),
    ('"tap: deshabilitado (\\(type == .tapDisabledByTimeout ? "timeout" : "user input")), reintentando"',
     '"tap: disabled (\\(type == .tapDisabledByTimeout ? "timeout" : "user input")), retrying"'),
    ('"salud: tap ausente, reinstalando"', '"health: tap missing, reinstalling"'),
    ('"salud: tap deshabilitado, reactivando"', '"health: tap disabled, re-enabling"'),

    # ---------------- PostProcessor / LLM ----------------
    ('"llm: llama.cpp respondió en \\(String(format: "%.1f", Date().timeIntervalSince(started)))s"',
     '"llm: llama.cpp answered in \\(String(format: "%.1f", Date().timeIntervalSince(started)))s"'),
    ('"llm: llama falló — \\(error.localizedDescription)"', '"llm: llama failed — \\(error.localizedDescription)"'),
    ('"llm: respondió en \\(String(format: "%.1f", elapsed))s"', '"llm: answered in \\(String(format: "%.1f", elapsed))s"'),
    ('"llm: salida vacía, uso texto crudo"', '"llm: empty output, using raw text"'),
    ('"llm: timeout tras \\(Int(timeout))s"', '"llm: timeout after \\(Int(timeout))s"'),
    ('"llm: modelo no disponible (\\(statusDescription))"', '"llm: model unavailable (\\(statusDescription))"'),
    ('"llm: error \\(error.localizedDescription)"', '"llm: error \\(error.localizedDescription)"'),
    ('"llm: texto limpio (\\(raw.count) -> \\(cleaned.count) chars)"', '"llm: cleaned text (\\(raw.count) -> \\(cleaned.count) chars)"'),
    ('"llm: descartado (\\(originalWords) -> \\(cleanedWords) palabras), uso texto crudo"',
     '"llm: rejected (\\(originalWords) -> \\(cleanedWords) words), using raw text"'),
    ('"llm: \\(words) palabras (< \\(config.postProcessMinWords)), se deja crudo"',
     '"llm: \\(words) words (< \\(config.postProcessMinWords)), leaving raw"'),
    ('"llm: sin backend (Apple: \\(statusDescription); llama: no instalado)"',
     '"llm: no backend (Apple: \\(statusDescription); llama: not installed)"'),
    ('"llm: sin limpieza, uso texto crudo"', '"llm: no cleanup, using raw text"'),
    ('"llm: sin cambios, uso texto crudo"', '"llm: no changes, using raw text"'),
    ('// Drop a leading "Aquí está el texto limpio:" style preamble.',
     '// Drop a leading "Here is the cleaned text:" style preamble.'),
    ('"aquí está el texto", "texto limpio:", "texto corregido:", "here is the"',
     '"here is the", "cleaned text:", "corrected text:"'),

    # ---------------- TextInserter ----------------
    ('"inserción: la app estaba activa, cediendo el foco"', '"insertion: app was active, yielding focus"'),
    ('"inserción: foco=[\\(focusDescription())] appActiva=\\(NSApp.isActive)"',
     '"insertion: focus=[\\(focusDescription())] appActive=\\(NSApp.isActive)"'),
    ('"inserción: destino=\\(destination) caret=\\(before?.caret.map(String.init) ?? "-") valor=\\(before?.valueLength.map(String.init) ?? "-")"',
     '"insertion: target=\\(destination) caret=\\(before?.caret.map(String.init) ?? "-") value=\\(before?.valueLength.map(String.init) ?? "-")"'),
    ('"inserción: AX no reporta el texto real (\\(before?.valueLength.map(String.init) ?? "nil")), se asume éxito tras ⌘V"',
     '"insertion: AX does not report real text (\\(before?.valueLength.map(String.init) ?? "nil")), assuming ⌘V worked"'),
    ('"inserción: verificada con ⌘V"', '"insertion: verified with ⌘V"'),
    ('"inserción: NO verificada"', '"insertion: NOT verified"'),
    ('"inserción: AX no reporta el texto real (\\(before?.valueLength.map(String.init) ?? "nil")), se asume éxito"',
     '"insertion: AX does not report real text (\\(before?.valueLength.map(String.init) ?? "nil")), assuming success"'),

    # ---------------- Transcriber ----------------
    ('"ffmpeg: sin respuesta tras \\(Int(timeout))s, terminando"', '"ffmpeg: no response after \\(Int(timeout))s, terminating"'),
    ('"\\(label): sin respuesta tras \\(Int(timeout))s, terminando"',
     '"\\(label): no response after \\(Int(timeout))s, terminating"'),

    # ---------------- TranscriptPanel / Store ----------------
    ('"historial exportado a \\(url.path)"', '"history exported to \\(url.path)"'),
    ('"fallback: texto copiado"', '"fallback: text copied"'),

    # ---------------- comments ----------------
    ('// Muletillas y palabras vacías: no aportan nada a un "diccionario" personal.',
     '// Filler and stop words: they add nothing to a personal "dictionary".'),
    ('// words like "pues", "este" or "o sea" are left alone because removing them',
     '// words like "pues", "este" or "o sea" are left alone because removing them'),
    ('// New sentence after terminators; "¿" and "¡" also start one.',
     '// New sentence after terminators; "¿" and "¡" also start one.'),
]


def main() -> None:
    files = sorted((ROOT / "Sources").glob("*.swift"))
    changed = 0
    for path in files:
        text = path.read_text()
        original = text
        for old, new in REPL:
            text = text.replace(old, new)
        if text != original:
            path.write_text(text)
            changed += 1
            print(f"updated: {path.name}")
    print(f"\n{changed} files changed")


if __name__ == "__main__":
    main()
