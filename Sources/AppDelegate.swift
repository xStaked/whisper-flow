import AppKit
import ApplicationServices
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum State {
        case idle
        case recording
        case transcribing
    }

    private var config = AppConfig.fallback
    private var store: TranscriptStore!
    private var transcriber: Transcriber!
    private var statusItem: NSStatusItem!
    private var state: State = .idle
    private var isBusy = false
    private var accessibilityTimer: Timer?

    private let monitor = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private let panel = TranscriptPanelController()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = Locator.loadOrDefault()
        Locator.save(config)

        store = TranscriptStore()
        transcriber = Transcriber(config: config)

        setupStatusItem()
        wireMonitor()

        recorder.onAutoStop = { [weak self] in
            self?.finishRecording()
        }

        AudioRecorder.requestPermission { _ in }

        if !startMonitor() {
            requestAccessibility()
        }

        showOnboardingIfNeeded()

        if ProcessInfo.processInfo.environment["WHISPERFLOW_SHOW_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.panel.show(store: self.store)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        recorder.cancel()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = Self.symbol("mic", tint: nil)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "WhisperFlow — mantén fn y habla"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            panel.toggle(store: store)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Últimos dictados", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Abrir permisos de accesibilidad", action: #selector(openAccessibilitySettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Abrir carpeta de configuración", action: #selector(openConfigFolder), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Salir de WhisperFlow", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openPanel() {
        panel.show(store: store)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(Locator.supportDir)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Hotkey

    private func wireMonitor() {
        monitor.onPress = { [weak self] in self?.beginRecording() }
        monitor.onRelease = { [weak self] in self?.finishRecording() }
        monitor.onCancel = { [weak self] in self?.cancelRecording() }
    }

    @discardableResult
    private func startMonitor() -> Bool {
        let started = monitor.start()
        if !started {
            scheduleAccessibilityRetry()
        }
        return started
    }

    private func requestAccessibility() {
        _ = TextInserter.accessibilityTrusted(prompt: true)
        scheduleAccessibilityRetry()
    }

    private func scheduleAccessibilityRetry() {
        guard accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted(), self.monitor.start() {
                timer.invalidate()
                self.accessibilityTimer = nil
                self.setState(.idle)
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Recording flow

    private func beginRecording() {
        guard !isBusy, state != .recording else { return }

        guard AudioRecorder.permissionGranted else {
            AudioRecorder.requestPermission { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.beginRecording()
                } else {
                    self.presentPermissionAlert(
                        title: "Falta el micrófono",
                        message: "Dale permiso de micrófono a WhisperFlow en Ajustes del Sistema → Privacidad y seguridad → Micrófono."
                    )
                }
            }
            return
        }

        do {
            try recorder.start(maxSeconds: config.maxRecordSeconds)
            playSound("Tink")
            setState(.recording)
        } catch {
            NSSound.beep()
            setState(.idle)
            presentError(error)
        }
    }

    private func finishRecording() {
        guard recorder.isRecording else { return }

        guard let audioURL = recorder.stop() else {
            setState(.idle)
            return
        }

        playSound("Pop")
        setState(.transcribing)
        isBusy = true

        let transcriber = self.transcriber!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let text = try transcriber.transcribe(recordingAt: audioURL)
                DispatchQueue.main.async {
                    self?.deliver(text)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.setState(.idle)
                    self.presentError(error)
                }
            }
        }
    }

    private func cancelRecording() {
        guard recorder.isRecording else { return }
        recorder.cancel()
        setState(.idle)
    }

    private func deliver(_ text: String) {
        store.add(text)

        var inserted = false
        if config.autoInsert {
            inserted = inserter.insert(text)
        }

        isBusy = false
        setState(.idle)

        if !inserted {
            // Could not verify the text landed in the app — show it so it can be copied.
            panel.show(store: store)
        }
    }

    // MARK: - UI helpers

    private func setState(_ newState: State) {
        state = newState
        guard let button = statusItem.button else { return }
        switch newState {
        case .idle:
            button.image = Self.symbol("mic", tint: nil)
        case .recording:
            button.image = Self.symbol("mic.fill", tint: .systemRed)
        case .transcribing:
            button.image = Self.symbol("waveform", tint: .systemOrange)
        }
    }

    private func playSound(_ name: String) {
        guard config.soundsEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private static func symbol(_ name: String, tint: NSColor?) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: "WhisperFlow") else {
            return nil
        }
        guard let tint else {
            base.isTemplate = true
            return base
        }
        let configured = base.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [tint])
        ) ?? base
        configured.isTemplate = false
        return configured
    }

    private func presentError(_ error: Error) {
        panel.show(store: store, error: "⚠️ \(error.localizedDescription)")
    }

    private func presentPermissionAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Ahora no")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            NSWorkspace.shared.open(url)
        }
    }

    private func showOnboardingIfNeeded() {
        let key = "WhisperFlowOnboarded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "WhisperFlow está listo"
        alert.informativeText = """
        Mantén presionada la tecla fn (🌐), habla, y suelta.

        El texto aparece en la app donde tengas el cursor. Si algo falla, el texto \
        queda en el panel (clic en el icono del micrófono) para que lo copies.

        Si al mantener fn se abre el emoji picker, ve a Ajustes del Sistema → \
        Teclado → "Presionar 🌐 para" → "No hacer nada".
        """
        alert.addButton(withTitle: "Entendido")
        alert.runModal()
    }
}
