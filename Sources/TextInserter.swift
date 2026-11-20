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
        Diagnostics.log("inserción: destino=\(destination) caret=\(before?.caret.map(String.init) ?? "-") valor=\(before?.valueLength.map(String.init) ?? "-")")

        // 1. Atomic paste: one event, so the text can never arrive half-written.
        pasteViaClipboard(trimmed)

        // Verification is only trustworthy when the app exposes its text through
        // Accessibility. Web views and Electron usually do not — guessing would
        // mean typing a second copy on top of a successful paste.
        guard let before, before.valueLength != nil else {
            Diagnostics.log("inserción: sin lectura del texto en destino, se asume éxito tras ⌘V")
            return true
        }
        if waitForValueChange(from: before) {
            Diagnostics.log("inserción: verificada con ⌘V")
            return true
        }

        // 2. ⌘V genuinely did nothing (blocked/disabled): type the characters.
        Diagnostics.log("inserción: ⌘V no cambió el texto, probando eventos Unicode")
        let beforeTyping = caretState()
        typeUnicode(trimmed)
        if let beforeTyping, beforeTyping.valueLength != nil, waitForValueChange(from: beforeTyping) {
            Diagnostics.log("inserción: verificada con eventos Unicode")
            return true
        }
        return false
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Strategy 1 — clipboard paste

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard a beat to publish before the target asks for it.
        usleep(30_000)

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // Only restore if our text is still there; never clobber a fresh copy.
            guard pasteboard.string(forType: .string) == text else { return }
            if let saved {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
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

    // MARK: Strategy 2 — unicode events

    private func typeUnicode(_ text: String) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let units = Array(text.utf16)
        var index = 0

        while index < units.count {
            var end = min(index + 20, units.count)
            // Never split a surrogate pair across two events.
            if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) {
                end -= 1
            }
            if end <= index { end = min(index + 2, units.count) }

            let chunk = Array(units[index..<end])
            chunk.withUnsafeBufferPointer { buffer in
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                down.post(tap: .cghidEventTap)
            }
            // The matching keyUp is what stops macOS from folding every follow-up
            // chunk into a single key-repeat and dropping it.
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }

            index = end
            usleep(8_000)
        }
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
