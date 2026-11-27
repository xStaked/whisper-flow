import AppKit

/// Floating, non-activating panel with the recent dictations.
///
/// It deliberately does NOT become the active app: when it appears because an
/// insertion failed, focus must stay in the app you were typing into.
final class TranscriptPanelController: NSObject {
    private var panel: NSPanel?
    private var stack: NSStackView?
    private var emptyView: NSView?
    private var errorLabel: NSTextField?
    private var copyAllButton: NSButton?
    private var clearButton: NSButton?
    private var countLabel: NSTextField?
    private weak var store: TranscriptStore?
    private var pendingError: String?

    private let panelWidth: CGFloat = 400
    private let panelHeight: CGFloat = 520
    private let rowWidth: CGFloat = 344

    func toggle(store: TranscriptStore) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show(store: store)
        }
    }

    func show(store: TranscriptStore, error: String? = nil) {
        self.store = store
        self.pendingError = error
        ensurePanel()
        rebuild()
        guard let panel else { return }
        place(panel)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    /// Called when a new dictation lands while the panel is open.
    func refreshIfVisible() {
        guard let panel, panel.isVisible, let store else { return }
        self.store = store
        rebuild()
    }

    // MARK: - Panel construction

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "History"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 340, height: 300)

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        // Header
        let header = NSTextField(labelWithString: "History")
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        header.translatesAutoresizingMaskIntoConstraints = false

        let count = NSTextField(labelWithString: "")
        count.font = .systemFont(ofSize: 11)
        count.textColor = .secondaryLabelColor
        count.translatesAutoresizingMaskIntoConstraints = false

        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.isHidden = true
        error.translatesAutoresizingMaskIntoConstraints = false

        // List
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 14, bottom: 12, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        // Empty state
        let empty = Self.makeEmptyState()
        effect.addSubview(empty)

        // Footer
        let copyAll = NSButton(title: "Copy all", target: self, action: #selector(copyAll))
        copyAll.bezelStyle = .rounded
        copyAll.controlSize = .small
        copyAll.translatesAutoresizingMaskIntoConstraints = false

        let export = NSButton(title: "Export", target: self, action: #selector(exportHistory))
        export.bezelStyle = .rounded
        export.controlSize = .small
        export.translatesAutoresizingMaskIntoConstraints = false
        export.toolTip = "Guardar todos los dictados como archivo Markdown"

        let clear = NSButton(title: "Delete", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        clear.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(header)
        effect.addSubview(count)
        effect.addSubview(error)
        effect.addSubview(scroll)
        effect.addSubview(copyAll)
        effect.addSubview(export)
        effect.addSubview(clear)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: effect.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),

            count.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            count.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),

            error.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            error.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            error.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: error.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 0),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: 0),
            scroll.bottomAnchor.constraint(equalTo: copyAll.topAnchor, constant: -8),

            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 24),
            empty.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -24),

            copyAll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            copyAll.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -14),

            clear.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            clear.centerYAnchor.constraint(equalTo: copyAll.centerYAnchor),

            export.trailingAnchor.constraint(equalTo: clear.leadingAnchor, constant: -8),
            export.centerYAnchor.constraint(equalTo: copyAll.centerYAnchor),
            export.leadingAnchor.constraint(greaterThanOrEqualTo: copyAll.trailingAnchor, constant: 8),

            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        ])

        panel.contentView = effect

        self.panel = panel
        self.stack = stack
        self.emptyView = empty
        self.errorLabel = error
        self.copyAllButton = copyAll
        self.clearButton = clear
        self.countLabel = count
    }

    private static func makeEmptyState() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        icon.contentTintColor = .tertiaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "No dictations yet")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString: "Hold the fn key, speak, and release.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: - Content

    private func rebuild() {
        guard let store, let stack else { return }

        if let error = pendingError {
            errorLabel?.stringValue = error
            errorLabel?.isHidden = false
        } else {
            errorLabel?.isHidden = true
        }
        pendingError = nil

        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let entries = Array(store.entries.prefix(20))
        emptyView?.isHidden = !entries.isEmpty
        copyAllButton?.isEnabled = !entries.isEmpty
        clearButton?.isEnabled = !entries.isEmpty
        countLabel?.stringValue = entries.isEmpty ? "" : "\(entries.count) de \(store.entries.count)"

        for entry in entries {
            let row = TranscriptRowView(entry: entry)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            stack.addArrangedSubview(row)
        }

        panel?.displayIfNeeded()
    }

    private func place(_ panel: NSPanel) {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: screen.maxX - size.width - 20,
                             y: screen.maxY - size.height - 20)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Actions

    @objc private func copyAll() {
        guard let store, !store.entries.isEmpty else { return }
        let all = store.entries.map(\.text).joined(separator: "\n\n")
        Clipboard.copy(all)
        flash(copyAllButton, title: "✓ Copiado")
    }

    @objc private func exportHistory() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.title = "Export history"
        panel.nameFieldStringValue = "dictados.md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        // The panel is shown from a non-activating window, so activate briefly.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            Diagnostics.log("history exported to \(url.path)")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Export failed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Delete the whole history?"
        alert.informativeText = "This deletes all \(store?.entries.count ?? 0) saved dictations. It cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        store?.clear()
        rebuild()
    }

    private func flash(_ button: NSButton?, title: String) {
        guard let button else { return }
        let original = button.title
        button.title = title
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            button.title = original
        }
    }
}
