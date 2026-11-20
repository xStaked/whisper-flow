import AppKit
import ApplicationServices

/// Types text into whatever app currently has focus.
///
/// Order of attack:
///   1. Clipboard + ⌘V — atomic. Web views and Electron only need one event, so
///      there is no chance of half the text arriving.
///   2. Unicode key events — for apps where ⌘V is disabled. Each chunk is a
///      keyDown/keyUp pair: consecutive keyDowns with the same virtual key are
///      interpreted as key-repeat and silently dropped.
///
/// Verification reads the caret/value through Accessibility. Electron apps are
/// famously unable to report their caret, so "cannot read it" must never be
/// treated as failure.
final class TextInserter {

    /// Every clipboard write bumps this. A pending "restore the old clipboard"
    /// only fires if nobody wrote to the clipboard in the meantime — otherwise it
    /// would silently roll back the text we had just copied for the user.
    private var clipboardGeneration = 0

    private struct CaretState: Equatable {
        let caret: Int?
        let valueLength: Int?
    }

    // MARK: Permissions

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Insertion

    @discardableResult
    func insert(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // If one of our own windows is key, keystrokes would land in our app.
        if NSApp.isActive {
            Diagnostics.log("inserción: la app estaba activa, cediendo el foco")
            NSApp.hide(nil)
            usleep(150_000)
        }

        let destination = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "desconocida"
        let before = caretState()
        Diagnostics.log("inserción: foco=[\(focusDescription())] appActiva=\(NSApp.isActive)")
        Diagnostics.log("inserción: destino=\(destination) caret=\(before?.caret.map(String.init) ?? "-") valor=\(before?.valueLength.map(String.init) ?? "-")")

        // 1. Atomic paste. Synthetic unicode typing only ever delivers its first
        //    chunk on macOS 26 (the rest gets swallowed), so a single ⌘V is the only
        //    way to be sure the whole text arrives at once.
        pasteViaClipboard(trimmed)

        // Verification is only trustworthy when the app exposes its text through
        // Accessibility. Web views usually do not; guessing there would duplicate text.
        // Web views often report a constant placeholder length (1, 14...) through
        // AX. That is not a usable signal, so treat it as "cannot verify".
        guard let before, let readable = before.valueLength, readable > 2 else {
            Diagnostics.log("inserción: AX no reporta el texto real (\(before?.valueLength.map(String.init) ?? "nil")), se asume éxito tras ⌘V")
            return true
        }
        if waitForValueChange(from: before) {
            Diagnostics.log("inserción: verificada con ⌘V")
            return true
        }

        // Nothing else is attempted on purpose. Typing after a paste that actually
        // worked would append a second, half-delivered copy of the text — and with
        // a broken AX value we cannot tell those two cases apart.
        return false
    }

    func copyToClipboard(_ text: String) {
        _ = writeClipboard(text)
    }

    @discardableResult
    private func writeClipboard(_ text: String) -> Int {
        clipboardGeneration += 1
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return clipboardGeneration
    }

    // MARK: Strategy 1 — clipboard paste

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let generation = writeClipboard(text)

        // Give the pasteboard a beat to publish before the target asks for it.
        usleep(30_000)

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.clipboardGeneration == generation else { return }
            guard pasteboard.string(forType: .string) == text, let saved else { return }
            self.clipboardGeneration += 1
            pasteboard.clearContents()
            pasteboard.setString(saved, forType: .string)
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey: CGKeyCode = 0x09

        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        usleep(8_000)
        if let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }
    }

    /// What actually has the keyboard focus, for diagnosing "nothing happens".
    private func focusDescription() -> String {
        guard AXIsProcessTrusted() else { return "sin permisos" }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return "sin foco"
        }
        let element = focusedRef as! AXUIElement

        var roleRef: CFTypeRef?
        var descRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)

        let role = (roleRef as? String) ?? "?"
        let description = (descRef as? String) ?? ""
        return description.isEmpty ? role : "\(role) · \(description)"
    }

    // MARK: Verification via Accessibility

    private func caretState() -> CaretState? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement

        var caret: Int?
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef,
           CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let value = rangeRef as! AXValue
            if AXValueGetType(value) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(value, .cfRange, &range) {
                    caret = range.location + range.length
                }
            }
        }

        var valueLength: Int?
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String {
            valueLength = text.utf16.count
        }

        guard caret != nil || valueLength != nil else { return nil }
        return CaretState(caret: caret, valueLength: valueLength)
    }

    private func waitForValueChange(from previous: CaretState) -> Bool {
        guard let old = previous.valueLength else { return false }
        for _ in 0..<14 {
            usleep(50_000)
            guard let current = caretState() else { continue }
            if let new = current.valueLength, new != old {
                return true
            }
        }
        return false
    }
}
