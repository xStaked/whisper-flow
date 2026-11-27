import AppKit

/// One row in the sidebar: icon, label, hover and selected states.
final class SidebarItemView: NSView {
    let sectionID: String
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badge = NSView()
    private var trackingArea: NSTrackingArea?
    private var onSelect: (() -> Void)?

    private(set) var isSelected = false

    init(identifier: String, title: String, symbol: String) {
        self.sectionID = identifier
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        iconView.contentTintColor = Theme.secondaryText
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Theme.secondaryText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    func onClick(_ action: @escaping () -> Void) {
        onSelect = action
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        layer?.backgroundColor = selected
            ? Theme.cardBackground.cgColor
            : NSColor.clear.cgColor
        iconView.contentTintColor = selected ? Theme.accent : Theme.secondaryText
        titleLabel.textColor = selected ? Theme.primaryText : Theme.secondaryText
        titleLabel.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .medium)
    }

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
        if !isSelected { layer?.backgroundColor = Theme.cardHover.withAlphaComponent(0.5).cgColor }
    }

    override func mouseExited(with event: NSEvent) {
        if !isSelected { layer?.backgroundColor = NSColor.clear.cgColor }
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }
}
