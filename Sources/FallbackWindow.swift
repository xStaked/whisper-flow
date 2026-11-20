import AppKit

/// Shown when the dictation could not be verified into the target app.
///
/// Unlike the history panel this window *does* activate: it exists to be used —
/// the text is editable and preselected, so ⌘C works immediately, like in Notes.
final class FallbackWindowController: NSObject {
    private var window: NSWindow?
    private var textView: NSTextView?
    private var statusLabel: NSTextField?

    func present(_ text: String) {
        ensureWindow()
        guard let window, let textView else { return }

        textView.string = text
        statusLabel?.stringValue = "No pude confirmar que el texto entrara en la app. Copialo de acá con ⌘C."

        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        textView.selectAll(nil)
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperFlow — texto para copiar"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 240)

        let content = NSView()

        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = textView

        let copyButton = NSButton(title: "Copiar", target: self, action: #selector(copyAll))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Cerrar", target: self, action: #selector(close))
        closeButton.bezelStyle = .rounded
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(status)
        content.addSubview(scroll)
        content.addSubview(copyButton)
        content.addSubview(closeButton)

        NSLayoutConstraint.activate([
            status.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

            copyButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            copyButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),

            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            closeButton.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
        ])

        window.contentView = content

        self.window = window
        self.textView = textView
        self.statusLabel = status
    }

    @objc private func copyAll() {
        guard let textView else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
        statusLabel?.stringValue = "Copiado ✓"
        Diagnostics.log("fallback: texto copiado")
    }

    @objc private func close() {
        window?.close()
    }
}
