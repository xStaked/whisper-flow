import AppKit
import AVFoundation

/// Live permission checklist. Shown on launch while something is missing, so the
/// user knows exactly which switch to flip instead of guessing why fn is dead.
final class SetupWindowController: NSObject {
    private var window: NSWindow?
    private var axRow: PermissionRowView?
    private var micRow: PermissionRowView?
    private var timer: Timer?
    private var onReady: (() -> Void)?

    func present(onReady: @escaping () -> Void) {
        self.onReady = onReady
        ensureWindow()
        refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperFlow permissions"
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSVisualEffectView()
        content.material = .windowBackground
        content.blendingMode = .behindWindow
        content.state = .active

        let title = NSTextField(wrappingLabelWithString: "WhisperFlow needs two permissions to work:")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let axRow = PermissionRowView(
            title: "Accessibility",
            detail: "To hear the fn key and type text into other apps.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )

        let micRow = PermissionRowView(
            title: "Microphone",
            detail: "To record your voice while you hold fn.",
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )

        let hint = NSTextField(wrappingLabelWithString: """
        If WhisperFlow is not in the list, press the button: it opens the right \
        panel and registers the app. Then switch it on.

        If holding fn opens the emoji picker, go to Settings → Keyboard → \
        "Press 🌐 to" → Do Nothing.
        """)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(title)
        content.addSubview(axRow)
        content.addSubview(micRow)
        content.addSubview(hint)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            axRow.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            axRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            axRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            micRow.topAnchor.constraint(equalTo: axRow.bottomAnchor, constant: 12),
            micRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            micRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),

            hint.topAnchor.constraint(equalTo: micRow.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
        ])

        window.contentView = content
        self.window = window
        self.axRow = axRow
        self.micRow = micRow
    }

    private func refresh() {
        let ax = AXIsProcessTrusted()
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

        axRow?.setGranted(ax)
        micRow?.setGranted(mic)

        if ax && mic {
            timer?.invalidate()
            timer = nil
            Diagnostics.log("permissions: both granted")
            onReady?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.window?.close()
            }
        }
    }
}

/// One row: label + live status + button that opens the right System Settings pane.
final class PermissionRowView: NSView {
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel: NSTextField

    init(title: String, detail: String, settingsURL: String) {
        detailLabel = NSTextField(wrappingLabelWithString: detail)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Open Settings", target: self, action: #selector(openSettings(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.translatesAutoresizingMaskIntoConstraints = false
        button.identifier = NSUserInterfaceItemIdentifier(settingsURL)

        addSubview(titleLabel)
        addSubview(statusLabel)
        addSubview(detailLabel)
        addSubview(button)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setGranted(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) no implementado") }

    func setGranted(_ granted: Bool) {
        statusLabel.stringValue = granted ? "granted ✓" : "missing ✗"
        statusLabel.textColor = granted ? .systemGreen : .systemRed
    }

    @objc private func openSettings(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        Diagnostics.log("permissions: opening \(raw)")
        NSWorkspace.shared.open(url)
    }
}
