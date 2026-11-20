import AppKit

/// Floating pill that shows what the app is doing, near the bottom of the screen.
///
/// Hard rules, because a decorative window must never break dictation:
///   - never becomes the active app (`nonactivatingPanel`)
///   - clicks pass through (`ignoresMouseEvents`)
///   - never takes keyboard focus, never appears in the window cycle
final class OverlayHUD {
    private var panel: NSPanel?
    private var waveform: WaveformView?
    private var iconView: NSImageView?
    private var timeLabel: NSTextField?
    private var statusLabel: NSTextField?

    private var ticker: Timer?
    private var startedAt: Date?
    private var hideWork: DispatchWorkItem?

    private let width: CGFloat = 236
    private let height: CGFloat = 54
    private let bottomInset: CGFloat = 100

    // MARK: - Public states

    func showRecording() {
        ensurePanel()
        guard let panel else { return }

        startedAt = Date()
        waveform?.isHidden = false
        waveform?.reset()
        timeLabel?.isHidden = false
        statusLabel?.isHidden = true
        iconView?.image = symbol("mic.fill", tint: .systemRed)
        timeLabel?.stringValue = "0:00"

        position()
        fadeIn(panel)
        startTicker()
    }

    func update(level: Float) {
        waveform?.push(CGFloat(max(0, min(1, level))))
    }

    func showTranscribing() {
        ensurePanel()
        guard let panel else { return }

        stopTicker()
        waveform?.isHidden = true
        timeLabel?.isHidden = true
        statusLabel?.isHidden = false
        statusLabel?.stringValue = "transcribiendo…"
        statusLabel?.textColor = NSColor.white.withAlphaComponent(0.85)
        iconView?.image = symbol("waveform", tint: .systemOrange)

        position()
        fadeIn(panel)
    }

    func showSuccess(_ message: String = "insertado") {
        ensurePanel()
        guard let panel else { return }

        stopTicker()
        waveform?.isHidden = true
        timeLabel?.isHidden = true
        statusLabel?.isHidden = false
        statusLabel?.stringValue = message
        statusLabel?.textColor = .systemGreen
        iconView?.image = symbol("checkmark.circle.fill", tint: .systemGreen)

        position()
        fadeIn(panel)
        scheduleHide(after: 0.9)
    }

    func showWarning(_ message: String) {
        ensurePanel()
        guard let panel else { return }

        stopTicker()
        waveform?.isHidden = true
        timeLabel?.isHidden = true
        statusLabel?.isHidden = false
        statusLabel?.stringValue = message
        statusLabel?.textColor = .systemOrange
        iconView?.image = symbol("exclamationmark.triangle.fill", tint: .systemOrange)

        position()
        fadeIn(panel)
        scheduleHide(after: 2.2)
    }

    func showCopied() {
        ensurePanel()
        guard let panel else { return }

        stopTicker()
        waveform?.isHidden = true
        timeLabel?.isHidden = true
        statusLabel?.isHidden = false
        statusLabel?.stringValue = "copiado al portapapeles"
        statusLabel?.textColor = .systemTeal
        iconView?.image = symbol("doc.on.clipboard.fill", tint: .systemTeal)

        position()
        fadeIn(panel)
        scheduleHide(after: 1.8)
    }

    func showError(_ message: String) {
        ensurePanel()
        guard let panel else { return }

        stopTicker()
        waveform?.isHidden = true
        timeLabel?.isHidden = true
        statusLabel?.isHidden = false
        statusLabel?.stringValue = message
        statusLabel?.textColor = .systemRed
        iconView?.image = symbol("xmark.octagon.fill", tint: .systemRed)

        position()
        fadeIn(panel)
        scheduleHide(after: 2.6)
    }

    func hide() {
        stopTicker()
        hideWork?.cancel()
        hideWork = nil
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    // MARK: - Build

    private func ensurePanel() {
        guard panel == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.alphaValue = 0

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = height / 2
        effect.layer?.masksToBounds = true

        let icon = NSImageView(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.contentTintColor = .systemRed

        let wave = WaveformView(frame: .zero)
        wave.translatesAutoresizingMaskIntoConstraints = false

        let time = NSTextField(labelWithString: "0:00")
        time.translatesAutoresizingMaskIntoConstraints = false
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        time.textColor = NSColor.white.withAlphaComponent(0.85)

        let status = NSTextField(labelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.textColor = NSColor.white.withAlphaComponent(0.85)
        status.isHidden = true

        effect.addSubview(icon)
        effect.addSubview(wave)
        effect.addSubview(time)
        effect.addSubview(status)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 16),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            wave.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            wave.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            wave.widthAnchor.constraint(equalToConstant: 118),
            wave.heightAnchor.constraint(equalToConstant: 24),

            time.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            time.centerYAnchor.constraint(equalTo: effect.centerYAnchor),

            status.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -16),
            status.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
        ])

        panel.contentView = effect

        self.panel = panel
        self.effect = effect
        self.iconView = icon
        self.waveform = wave
        self.timeLabel = time
        self.statusLabel = status
    }

    private var effect: NSVisualEffectView?

    // MARK: - Ticker (only while recording)

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.waveform?.decay()
            self.updateElapsed()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func updateElapsed() {
        guard let startedAt else { return }
        let seconds = Int(Date().timeIntervalSince(startedAt))
        timeLabel?.stringValue = String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Placement

    private func position() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visible.midX - width / 2,
            y: visible.minY + bottomInset
        )
        panel.setFrameOrigin(origin)
    }

    private func fadeIn(_ panel: NSPanel) {
        hideWork?.cancel()
        hideWork = nil
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func symbol(_ name: String, tint: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}

/// Live level meter: the bars are the actual microphone RMS, not decoration.
final class WaveformView: NSView {
    private var levels: [CGFloat] = Array(repeating: 0, count: 24)
    private let barWidth: CGFloat = 3
    private let gap: CGFloat = 2

    override var isFlipped: Bool { false }

    func reset() {
        levels = Array(repeating: 0, count: levels.count)
        needsDisplay = true
    }

    func push(_ level: CGFloat) {
        levels.removeFirst()
        levels.append(level)
        needsDisplay = true
    }

    /// Bars fall back down when there is no new audio, so silence looks silent.
    func decay() {
        var changed = false
        for index in levels.indices where levels[index] > 0.01 {
            levels[index] *= 0.88
            changed = true
        }
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.9).setFill()

        let totalWidth = CGFloat(levels.count) * barWidth + CGFloat(levels.count - 1) * gap
        var x = (bounds.width - totalWidth) / 2
        let midY = bounds.midY

        for level in levels {
            let barHeight = max(2, level * bounds.height)
            let rect = NSRect(x: x, y: midY - barHeight / 2, width: barWidth, height: barHeight)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }
}
