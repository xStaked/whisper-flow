import AppKit

/// A dictation in the main window: large readable text, timestamp and actions.
final class DictationCardView: NSView {
    let entry: TranscriptEntry
    private(set) var searchText: String

    private let textView = NSTextView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let actions = NSStackView()
    private var trackingArea: NSTrackingArea?
    private var onCopied: (() -> Void)?

    private let cardInset: CGFloat = 16

    init(entry: TranscriptEntry) {
        self.entry = entry
        self.searchText = entry.text
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = Theme.cardRadius
        layer?.backgroundColor = Theme.cardBackground.cgColor

        // Body text: selectable so ⌘C works natively too.
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.font = .systemFont(ofSize: 12.5)
        textView.textColor = Theme.primaryText
        textView.string = entry.text
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        // A scroll view adds nothing here: the card must grow with its text. The
        // text view reports its own height through an explicit constraint so the
        // stack view can size the card.
        textView.translatesAutoresizingMaskIntoConstraints = false

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.stringValue = formatter.string(from: entry.date)
        timeLabel.font = Theme.caption(10.5)
        timeLabel.textColor = Theme.tertiaryText
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        actions.orientation = .horizontal
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.alphaValue = 0

        let copy = iconButton("doc.on.doc", tooltip: "Copiar") { [weak self] in
            guard let self else { return }
            Clipboard.copy(self.entry.text)
            self.onCopied?()
            self.flashCopy()
        }
        let edit = iconButton("square.and.pencil", tooltip: "Copiar y editar") { [weak self] in
            guard let self else { return }
            Clipboard.copy(self.entry.text)
            self.onCopied?()
            self.flashCopy()
        }
        actions.addArrangedSubview(copy)
        actions.addArrangedSubview(edit)

        addSubview(textView)
        addSubview(timeLabel)
        addSubview(actions)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor, constant: cardInset),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: cardInset),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -cardInset),

            timeLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 12),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: cardInset),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -cardInset),

            actions.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -cardInset),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    /// One constraint, updated in place. Activating a new one on every layout pass
    /// piles up constraints and breaks the stack view's spacing.
    private var textHeightConstraint: NSLayoutConstraint?

    override func layout() {
        super.layout()
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        let width = textView.bounds.width
        guard width > 10 else { return }

        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = ceil(layout.usedRect(for: container).height) + 1
        guard used > 1 else { return }

        if let constraint = textHeightConstraint {
            if abs(constraint.constant - used) > 0.5 { constraint.constant = used }
        } else {
            let constraint = textView.heightAnchor.constraint(equalToConstant: used)
            constraint.isActive = true
            textHeightConstraint = constraint
        }
    }

    func onCopy(_ action: @escaping () -> Void) {
        onCopied = action
    }

    private func iconButton(_ symbol: String, tooltip: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = Theme.secondaryText
        button.isBordered = false
        button.title = ""
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(handleButton(_:))
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
        button.heightAnchor.constraint(equalToConstant: 22).isActive = true
        buttonMap[button] = action
        return button
    }

    private var buttonMap: [NSButton: () -> Void] = [:]

    @objc private func handleButton(_ sender: NSButton) {
        buttonMap[sender]?()
    }

    private func flashCopy() {
        timeLabel.stringValue = "✓ copiado"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            self.timeLabel.stringValue = formatter.string(from: self.entry.date)
        }
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Theme.cardHover.cgColor
        actions.alphaValue = 1
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = Theme.cardBackground.cgColor
        actions.alphaValue = 0
    }

    func setHighlighted(_ highlighted: Bool) {
        layer?.borderWidth = highlighted ? 2 : 0
        layer?.borderColor = highlighted ? Theme.accent.cgColor : nil
    }
}
