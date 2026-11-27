import AppKit

/// The single owner of the system clipboard.
///
/// Every write the app makes goes through here so that a pending
/// "restore the clipboard I stole for a paste" can be *cancelled by any newer
/// copy*. Without that, clicking "Copiar" right after a dictation used to hand
/// you back whatever was on the clipboard before, which looked like random text.
enum Clipboard {
    /// Bumped on every write. A scheduled restore only fires if the value is
    /// still the one it wrote.
    private static var generation = 0
    private static let lock = NSLock()

    /// - Returns: the generation of this write, to be compared later.
    @discardableResult
    static func write(_ text: String) -> Int {
        lock.lock()
        generation += 1
        let current = generation
        lock.unlock()

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return current
    }

    /// Copy now, no restore, no surprises.
    static func copy(_ text: String) {
        write(text)
        Diagnostics.log("portapapeles: copiado (\(text.count) caracteres)")
    }

    static func currentText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Writes `text` for a ⌘V and puts `previous` back afterwards — but only if
    /// nobody copied anything in the meantime.
    static func writeTemporarily(_ text: String, restoring previous: String?, after delay: TimeInterval) {
        let written = write(text)
        guard let previous else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            lock.lock()
            let unchanged = generation == written
            lock.unlock()

            guard unchanged, currentText() == text else {
                Diagnostics.log("portapapeles: no se restaura, hubo una copia nueva")
                return
            }
            write(previous)
            Diagnostics.log("portapapeles: restaurado el contenido anterior")
        }
    }
}
