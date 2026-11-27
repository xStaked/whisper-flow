import AppKit

/// One dictation in the history list: text, timestamp and its own copy button.
///
/// The text lives in a real selectable text view so ⌘C works natively too, and
/// the row highlights on hover so it is obvious what will be copied.
final class TranscriptRowView: NSView {
    private let textView = NSTextView()
    private let timeLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let entry: TranscriptEntry
    private var trackingArea: NSTrackingArea?

    private let inset: CGFloat = 10

    init(entry: TranscriptEntry) {
        self.entry = entry
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor

        // Text: selectable, non-editable, wrapping.
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.string = entry.text
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainer?.lineFragmentPadding = 0

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.verticalScrollElasticity = .none

        // Size the text view to its content.
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeLabel.stringValue = formatter.string(from: entry.date)
        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        copyButton.title = "Copy"
        copyButton.bezelStyle = .inline
        copyButton.isBordered = false
        copyButton.controlSize = .small
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.font = .systemFont(ofSize: 11, weight: .medium)
        copyButton.target = self
        copyButton.action = #selector(copyEntry)
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.toolTip = "Copiar este dictado al portapapeles"

        addSubview(scroll)
        addSubview(timeLabel)
        addSubview(copyButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            timeLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            timeLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            timeLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),

            copyButton.centerYAnchor.constraint(equalTo: timeLabel.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            copyButton.leadingAnchor.constraint(greaterThanOrEqualTo: timeLabel.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    }

    // MARK: Copy

    @objc private func copyEntry() {
        Clipboard.copy(entry.text)
        flashCopied()
    }

    private func flashCopied() {
        copyButton.title = "✓ Copied"
        copyButton.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.copyButton.title = "Copy"
            self?.copyButton.contentTintColor = .secondaryLabelColor
        }
    }
}
