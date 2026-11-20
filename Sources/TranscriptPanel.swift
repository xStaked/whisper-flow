import AppKit

/// Floating, non-activating panel with the recent dictations.
///
/// It deliberately does NOT become the active app: when it appears because an
/// insertion failed, focus must stay in the app you were typing into.
final class TranscriptPanelController: NSObject {
    private var panel: NSPanel?
    private var stack: NSStackView?
    private var emptyLabel: NSTextField?
    private var errorLabel: NSTextField?
    private var copyButton: NSButton?
    private weak var store: TranscriptStore?
    private var pendingError: String?

    private let panelWidth: CGFloat = 400
    private let rowWidth: CGFloat = 352

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

    // MARK: - Panel construction

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 480),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "WhisperFlow"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active

        let header = NSTextField(labelWithString: "Últimos dictados")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.translatesAutoresizingMaskIntoConstraints = false

        let error = NSTextField(wrappingLabelWithString: "")
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.isHidden = true
        error.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        let empty = NSTextField(wrappingLabelWithString: "Todavía no dictaste nada.\nMantén fn y habla.")
        empty.font = .systemFont(ofSize: 12)
        empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(empty)

        let copy = NSButton(title: "Copiar último", target: self, action: #selector(copyLatest))
        copy.bezelStyle = .rounded
        copy.controlSize = .small
        copy.translatesAutoresizingMaskIntoConstraints = false

        let clear = NSButton(title: "Borrar historial", target: self, action: #selector(clearHistory))
        clear.bezelStyle = .rounded
        clear.controlSize = .small
        clear.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(header)
        effect.addSubview(error)
        effect.addSubview(scroll)
        effect.addSubview(empty)
        effect.addSubview(copy)
        effect.addSubview(clear)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),

            error.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            error.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            error.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),

            scroll.topAnchor.constraint(equalTo: error.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: copy.topAnchor, constant: -10),

            empty.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 12),
            empty.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),

            copy.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            copy.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),

            clear.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            clear.centerYAnchor.constraint(equalTo: copy.centerYAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
        ])

        panel.contentView = effect

        self.panel = panel
        self.stack = stack
        self.emptyLabel = empty
        self.errorLabel = error
        self.copyButton = copy
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
        emptyLabel?.isHidden = !entries.isEmpty
        copyButton?.isEnabled = !entries.isEmpty

        for entry in entries {
            let row = NSTextField(wrappingLabelWithString: entry.text)
            row.font = .systemFont(ofSize: 12)
            row.textColor = .labelColor
            row.isSelectable = true
            row.preferredMaxLayoutWidth = rowWidth
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

    @objc private func copyLatest() {
        guard let text = store?.entries.first?.text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        copyButton?.title = "Copiado ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton?.title = "Copiar último"
        }
    }

    @objc private func clearHistory() {
        store?.clear()
        rebuild()
    }
}
