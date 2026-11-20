import AppKit
import ApplicationServices

/// Types text into whatever app currently has focus.
///
/// Two strategies, in order of preference:
///   1. Unicode CGEvent typing — leaves the clipboard untouched.
///   2. Clipboard + ⌘V — slower and clobbers the clipboard briefly, but works
///      in apps that ignore synthesised unicode (some Electron/web views).
///
/// If neither can be verified, the caller opens the panel so the text is never lost.
final class TextInserter {

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

        let before = caretSignature()
        typeUnicode(trimmed)

        if let before, waitForCaretChange(from: before) { return true }
        if before == nil { return true } // cannot verify — assume it worked

        // Fallback: clipboard paste.
        let snapshot = before
        pasteViaClipboard(trimmed)
        if let snapshot, waitForCaretChange(from: snapshot) { return true }
        return false
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: Strategy 1 — unicode events

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
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
                event.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                event.post(tap: .cghidEventTap)
            }
            index = end
            usleep(4_000)
        }
    }

    // MARK: Strategy 2 — clipboard paste

    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let vKey: CGKeyCode = 0x09 // V

        if let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cghidEventTap)
        }

        // Give the target app time to read the pasteboard before restoring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let saved {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    // MARK: Verification via Accessibility

    private func caretSignature() -> Int? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef,
              CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else {
            return nil
        }
        let element = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rangeRef,
           CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let value = rangeRef as! AXValue
            if AXValueGetType(value) == .cfRange {
                var range = CFRange()
                if AXValueGetValue(value, .cfRange, &range) {
                    return range.location + range.length
                }
            }
        }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let text = valueRef as? String {
            return text.utf16.count
        }
        return nil
    }

    private func waitForCaretChange(from signature: Int) -> Bool {
        for _ in 0..<8 {
            usleep(40_000)
            if let current = caretSignature(), current != signature {
                return true
            }
        }
        return false
    }
}
