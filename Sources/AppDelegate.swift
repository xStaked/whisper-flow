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
    /// `AVAudioEngine.start()` can block for seconds while audio devices change
    /// (plugging headphones). The fn release may arrive before it returns.
    private enum PendingAction { case none, stop, cancel }
    private var pendingAction: PendingAction = .none
    private var startInFlight = false
    private var hotkeyHealthTimer: Timer?

    private let monitor = FnKeyMonitor()
    private let recorder = AudioRecorder()
    private let inserter = TextInserter()
    private let panel = TranscriptPanelController()
    private let setup = SetupWindowController()
    private let hud = OverlayHUD()

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.reset()

        config = Locator.loadOrDefault()
        Locator.save(config)

        Diagnostics.log("--- WhisperFlow arrancó ---")
        Diagnostics.log("accesibilidad concedida: \(AXIsProcessTrusted())")
        Diagnostics.log("micrófono: \(AudioRecorder.permissionStatusDescription)")
        Diagnostics.log("modelo: \(config.modelPath)")
        Diagnostics.log("whisper-cli: \(config.whisperBinaryPath)")
        Diagnostics.log("ffmpeg: \(config.ffmpegPath)")
        Diagnostics.log("idioma: \(config.language)")

        store = TranscriptStore()
        transcriber = Transcriber(config: config)

        setupStatusItem()
        wireMonitor()

        recorder.onAutoStop = { [weak self] in
            self?.finishRecording()
        }
        recorder.onLevel = { [weak self] level in
            self?.hud.update(level: level)
        }

        AudioRecorder.requestPermission { _ in }

        if !startMonitor() {
            requestAccessibility()
        }

        if !(AXIsProcessTrusted() && AudioRecorder.permissionGranted) {
            setup.present { [weak self] in
                self?.startMonitor()
                self?.setState(.idle)
            }
        } else {
            // `open` (and Login Items) can leave us as the active app. With no
            // windows that means keystrokes have nowhere to land, so give focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let hasVisibleWindow = NSApp.windows.contains { $0.isVisible }
                if NSApp.isActive, !hasVisibleWindow {
                    Diagnostics.log("arranque: quedé activa sin ventanas, cediendo el foco")
                    NSApp.hide(nil)
                }
            }
        }

        // Self-healing: macOS can disable a tap (sleep, device changes, timeouts).
        // Reinstalling it quietly beats a hotkey that dies hours later.
        hotkeyHealthTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, AXIsProcessTrusted() else { return }
            if !self.monitor.isRunning {
                Diagnostics.log("salud: tap ausente, reinstalando")
                self.monitor.start()
                self.setState(.idle)
            } else if !self.monitor.isEnabled {
                Diagnostics.log("salud: tap deshabilitado, reactivando")
                self.monitor.reenable()
            }

            // La píldora no puede quedarse animando si no hay grabación real.
            if self.hud.isShowingRecording, !self.recorder.isRecording, !self.startInFlight {
                Diagnostics.log("salud: píldora grabando sin grabación, se oculta")
                self.hud.hide()
                self.setState(.idle)
            }
        }

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
            return
        }

        // Without Accessibility there is no hotkey and no typing — make that loud.
        guard AXIsProcessTrusted() else {
            Diagnostics.log("clic: falta accesibilidad, abriendo ajustes")
            _ = TextInserter.accessibilityTrusted(prompt: true)
            openAccessibilitySettings()
            scheduleAccessibilityRetry()
            return
        }

        panel.toggle(store: store)
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Últimos dictados", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Re-insertar último dictado", action: #selector(reinsertLast), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Abrir permisos", action: #selector(openSetup), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Abrir carpeta de configuración", action: #selector(openConfigFolder), keyEquivalent: "").target = self

        menu.addItem(NSMenuItem.separator())
        let cleanupHeader = NSMenuItem(title: "Limpieza del texto", action: nil, keyEquivalent: "")
        cleanupHeader.isEnabled = false
        menu.addItem(cleanupHeader)

        let offItem = NSMenuItem(title: "Desactivada", action: #selector(setCleanupOff), keyEquivalent: "")
        offItem.target = self
        offItem.state = config.postProcess ? .off : .on
        menu.addItem(offItem)

        let rulesItem = NSMenuItem(title: "Reglas (instantáneo)", action: #selector(setCleanupRules), keyEquivalent: "")
        rulesItem.target = self
        rulesItem.state = (config.postProcess && config.postProcessEngine.lowercased() != "llm") ? .on : .off
        menu.addItem(rulesItem)

        let llmItem = NSMenuItem(title: "IA local (+4s)", action: #selector(setCleanupLLM), keyEquivalent: "")
        llmItem.target = self
        llmItem.state = (config.postProcess && config.postProcessEngine.lowercased() == "llm") ? .on : .off
        menu.addItem(llmItem)

        menu.addItem(NSMenuItem.separator())
        let hudItem = NSMenuItem(title: "Indicador en pantalla", action: #selector(toggleOverlay), keyEquivalent: "")
        hudItem.target = self
        hudItem.state = config.showOverlay ? .on : .off
        menu.addItem(hudItem)
        menu.addItem(withTitle: "Ver log de diagnóstico", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Salir de WhisperFlow", action: #selector(quit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    /// Retry insertion from history without re-dictating — handy when the target
    /// app was not focused the first time.
    @objc private func reinsertLast() {
        guard let text = store.entries.first?.text else {
            NSSound.beep()
            return
        }
        let inserted = inserter.insert(text)
        Diagnostics.log("reinsertar: \(inserted ? "verificada" : "falló")")
        if !inserted {
            inserter.copyToClipboard(text)
            if config.showOverlay { hud.showCopied() }
        }
    }

    @objc private func openPanel() {
        panel.show(store: store)
    }

    @objc private func openConfigFolder() {
        NSWorkspace.shared.open(Locator.supportDir)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Diagnostics.logURL)
    }

    @objc private func toggleOverlay() {
        config.showOverlay.toggle()
        Locator.save(config)
        Diagnostics.log("config: overlay = \(config.showOverlay)")
        if !config.showOverlay { hud.hide() }
    }

    @objc private func setCleanupOff() { updateCleanup(enabled: false, engine: "rules") }
    @objc private func setCleanupRules() { updateCleanup(enabled: true, engine: "rules") }
    @objc private func setCleanupLLM() { updateCleanup(enabled: true, engine: "llm") }

    private func updateCleanup(enabled: Bool, engine: String) {
        config.postProcess = enabled
        config.postProcessEngine = engine
        Locator.save(config)
        Diagnostics.log("config: limpieza = \(enabled ? engine : "off")")
    }

    @objc private func openSetup() {
        setup.present { [weak self] in
            self?.startMonitor()
            self?.setState(.idle)
        }
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
        Diagnostics.log("onPress: busy=\(isBusy) recording=\(recorder.isRecording) mic=\(AudioRecorder.permissionStatusDescription)")

        guard !isBusy, !recorder.isRecording else {
            Diagnostics.log("onPress: ignorado porque estaba ocupado")
            return
        }

        guard AudioRecorder.permissionGranted else {
            Diagnostics.log("onPress: sin permiso de micrófono")
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

        startInFlight = true
        pendingAction = .none
        let maxSeconds = config.maxRecordSeconds

        do {
            try recorder.start(maxSeconds: maxSeconds)
        } catch {
            // A device that just appeared/disappeared is usually ready a moment
            // later; one short retry avoids losing the dictation.
            Diagnostics.log("grabación: primer intento falló (\(error.localizedDescription)), reintentando")
            usleep(250_000)
            do {
                try recorder.start(maxSeconds: maxSeconds)
            } catch {
                startInFlight = false
                pendingAction = .none
                Diagnostics.log("grabación: error \(error.localizedDescription)")
                NSSound.beep()
                setState(.idle)
                hud.hide()
                if config.showOverlay { hud.showError("no se pudo grabar") }
                presentError(error)
                return
            }
        }

        startInFlight = false

        switch pendingAction {
        case .cancel:
            pendingAction = .none
            Diagnostics.log("grabación: fn se soltó durante el arranque, se descarta")
            recorder.cancel()
            setState(.idle)
            hud.hide()
        case .stop:
            pendingAction = .none
            Diagnostics.log("grabación: fn se soltó durante el arranque, se cierra ya")
            finishRecording()
        case .none:
            Diagnostics.log("grabación: empezó")
            if config.showOverlay { hud.showRecording() }
            playSound("Tink")
            setState(.recording)
        }
    }

    private func finishRecording() {
        if startInFlight {
            pendingAction = .stop
            Diagnostics.log("onRelease: el arranque seguía en curso, se cerrará al terminar")
            return
        }

        guard recorder.isRecording else {
            Diagnostics.log("onRelease: no había grabación activa")
            return
        }

        guard let capture = recorder.stop() else {
            Diagnostics.log("onRelease: el audio quedó vacío")
            setState(.idle)
            return
        }

        playSound("Pop")
        if config.showOverlay { hud.showTranscribing() }
        Diagnostics.log("grabación: terminó (\(String(format: "%.1f", capture.durationSeconds))s), transcribiendo")
        setState(.transcribing)
        isBusy = true
        startWatchdog()

        let transcriber = self.transcriber!
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let audioURL = AudioRecorder.writeWav(capture) else {
                DispatchQueue.main.async {
                    self?.isBusy = false
                    self?.setState(.idle)
                    self?.presentError(RecorderError.couldNotWriteFile)
                }
                return
            }
            do {
                let raw = try transcriber.transcribe(recordingAt: audioURL)
                let text = self?.applyPostProcessing(raw) ?? raw
                DispatchQueue.main.async {
                    self?.deliver(text)
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    Diagnostics.log("transcripción: error \(error.localizedDescription)")
                    self.isBusy = false
                    self.setState(.idle)
                    self.presentError(error)
                }
            }
        }
    }

    /// If the pipeline ever wedges, free the state instead of staying busy forever —
    /// a stuck `isBusy` is what silently kills the hotkey.
    private func startWatchdog() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.isBusy else { return }
            Diagnostics.log("watchdog: 120s ocupado, liberando estado")
            self.isBusy = false
            self.setState(.idle)
        }
    }

    private func cancelRecording() {
        if startInFlight {
            pendingAction = .cancel
            Diagnostics.log("onCancel: el arranque seguía en curso, se descartará")
            return
        }

        guard recorder.isRecording else { return }
        recorder.cancel()
        setState(.idle)
        hud.hide()
    }

    /// Optional on-device cleanup. Runs on the transcription queue so it never
    /// touches the main thread or the hotkey.
    private func applyPostProcessing(_ raw: String) -> String {
        guard config.postProcess else { return raw }

        // Short commands are already fine and latency matters more there.
        let words = raw.split(whereSeparator: { $0.isWhitespace }).count
        guard words >= config.postProcessMinWords else {
            Diagnostics.log("llm: \(words) palabras (< \(config.postProcessMinWords)), se deja crudo")
            return raw
        }

        if config.postProcessEngine.lowercased() == "llm" {
            guard let cleaned = PostProcessor.clean(raw, config: config) else {
                Diagnostics.log("llm: sin limpieza, uso texto crudo")
                return raw
            }
            Diagnostics.log("llm: texto limpio (\(raw.count) -> \(cleaned.count) chars)")
            return cleaned
        }

        let cleaned = RulesCleaner.clean(raw)
        guard !cleaned.isEmpty else { return raw }
        Diagnostics.log("reglas: texto limpio (\(raw.count) -> \(cleaned.count) chars)")
        return cleaned
    }

    private func deliver(_ text: String) {
        Diagnostics.log("texto: \(text)")
        store.add(text)

        var inserted = false
        if config.autoInsert {
            inserted = inserter.insert(text)
            Diagnostics.log("inserción: \(inserted ? "verificada" : "NO verificada")")
        } else {
            Diagnostics.log("inserción: desactivada (autoInsert=false)")
        }

        isBusy = false
        setState(.idle)

        if config.showOverlay {
            if inserted {
                hud.showSuccess()
            } else {
                hud.showWarning("no se pudo pegar")
            }
        }

        if !inserted {
            // Never open a window here: activating would steal focus and the next
            // dictation would be typed into our own app instead of yours.
            inserter.copyToClipboard(text)
            Diagnostics.log("inserción fallida: texto copiado al portapapeles")
            if config.showOverlay { hud.showCopied() }
        }
    }

    // MARK: - UI helpers

    private func setState(_ newState: State) {
        state = newState
        guard let button = statusItem.button else { return }
        switch newState {
        case .idle:
            if AXIsProcessTrusted() {
                button.image = Self.symbol("mic", tint: nil)
                button.toolTip = "WhisperFlow — mantén fn y habla"
            } else {
                button.image = Self.symbol("mic.slash", tint: nil)
                button.toolTip = "WhisperFlow — falta el permiso de Accesibilidad (haz clic)"
            }
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
        if config.showOverlay { hud.showError("error al transcribir") }
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
}
