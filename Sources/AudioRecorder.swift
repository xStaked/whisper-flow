import AVFoundation
import Foundation

enum RecorderError: LocalizedError {
    case noInputDevice
    case permissionDenied
    case couldNotWriteFile

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No se detectó ningún micrófono."
        case .permissionDenied:
            return "Falta el permiso de micrófono (Ajustes del Sistema → Privacidad y seguridad → Micrófono)."
        case .couldNotWriteFile:
            return "No se pudo guardar el audio temporal."
        }
    }
}

/// Audio captured in memory, ready to be encoded off the main thread.
struct CapturedAudio {
    let samples: [Float]
    let sampleRate: Double

    var durationSeconds: Double {
        sampleRate > 0 ? Double(samples.count) / sampleRate : 0
    }
}

/// Captures the microphone into memory and returns it as samples.
///
/// A brand new AVAudioEngine is created for every recording on purpose: a reused
/// engine goes stale after audio devices come and go (AirPods, USB mics, sleep)
/// and `engine.start()` can then block for seconds — which previously froze the
/// hotkey's event tap until macOS disabled it.
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 48_000
    private var autoStopWork: DispatchWorkItem?
    private var configObserver: NSObjectProtocol?
    private var startedAt = Date()
    private var lastBufferAt: Date?

    private(set) var isRecording = false
    var onAutoStop: (() -> Void)?
    /// Called ~12 times per second with the current input level (0...1).
    var onLevel: ((Float) -> Void)?
    /// Rolling reference so the meter adapts to the microphone's actual loudness.
    private var adaptivePeak: Float = 0.60

    static var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var permissionStatusDescription: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    static func requestPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    func start(maxSeconds: Double) throws {
        guard !isRecording else { return }
        guard Self.permissionGranted else { throw RecorderError.permissionDenied }

        finish() // clear any residue from a previous attempt

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInputDevice }

        Diagnostics.log("audio: \(Int(format.sampleRate)) Hz · \(format.channelCount) canal(es)")
        startedAt = Date()
        sampleRate = format.sampleRate
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }

        self.engine = engine
        isRecording = true

        // Unplugging the mic or switching output device mid-dictation kills the tap;
        // close the recording so the audio captured so far is still transcribed.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }

            // Bluetooth headsets switch into "headset" profile when the engine
            // starts, which fires a configuration change immediately. Closing the
            // recording there meant Bluetooth mics could never record anything.
            let age = Date().timeIntervalSince(self.startedAt)
            if age < 2.0 {
                Diagnostics.log("audio: reconfiguración de arranque ignorada (\(String(format: "%.2f", age))s)")
                if !engine.isRunning {
                    do { try engine.start() } catch {
                        Diagnostics.log("audio: no se pudo reanudar — \(error.localizedDescription)")
                    }
                }
                return
            }

            Diagnostics.log("audio: cambió el dispositivo a mitad de grabación, cerrando")
            self.onAutoStop?()
        }

        // If the profile switch invalidated the tap we would record pure silence.
        // Check that buffers are actually flowing and reinstall the tap if not.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.isRecording, self.lastBufferAt == nil else { return }
            Diagnostics.log("audio: no llegaron muestras, reinstalando el tap")
            self.reinstallTap()
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            Diagnostics.log("audio: límite de \(Int(maxSeconds))s alcanzado")
            self.onAutoStop?()
        }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds, execute: work)
    }

    func stop() -> CapturedAudio? {
        guard isRecording else { return nil }
        finish()

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        guard !captured.isEmpty else { return nil }
        return CapturedAudio(samples: captured, sampleRate: sampleRate)
    }

    func cancel() {
        finish()
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    /// Rebuilds the input tap against the device's current format, keeping the
    /// audio captured so far.
    private func reinstallTap() {
        guard let engine, isRecording else { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            Diagnostics.log("audio: el dispositivo no reporta formato válido")
            return
        }

        input.removeTap(onBus: 0)
        lock.lock()
        let alreadyCaptured = !samples.isEmpty
        lock.unlock()
        if !alreadyCaptured { sampleRate = format.sampleRate }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                Diagnostics.log("audio: no se pudo reanudar — \(error.localizedDescription)")
            }
        }
        Diagnostics.log("audio: tap reinstalado a \(Int(format.sampleRate)) Hz")
    }

    private func finish() {
        autoStopWork?.cancel()
        autoStopWork = nil

        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }

        if let engine {
            if engine.isRunning {
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
            }
            self.engine = nil
        }
        isRecording = false
        lastBufferAt = nil
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let channelCount = Int(buffer.format.channelCount)

        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channelCount {
            let source = channels[c]
            for i in 0..<frames { mono[i] += source[i] }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for i in 0..<frames { mono[i] *= scale }
        }

        lastBufferAt = Date()
        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()

        if let onLevel {
            var sum: Float = 0
            for value in mono { sum += value * value }
            let rms = (sum / Float(mono.count)).squareRoot()

            // RMS is a poor meter on its own: normal speech sits near 0.02-0.05,
            // which a linear scale renders as a dead bar. Work in dBFS instead:
            // -55 dB = silence, -10 dB = loud speech.
            let decibels = 20 * log10(max(rms, 1e-7))
            var level = (decibels + 52) / 40
            level = min(1, max(0, level))

            // Adaptive gain: a quiet mic (AirPods, built-in, noisy room) still
            // fills the meter, and the reference decays slowly when you go silent.
            adaptivePeak = max(level, adaptivePeak * 0.995)
            let scale = 1 / max(0.60, adaptivePeak)
            let shown = pow(min(1, level * scale), 0.9)

            DispatchQueue.main.async { onLevel(shown) }
        }
    }

    /// Encodes to 16-bit PCM WAV. Called off the main thread — never from the
    /// event tap callback.
    static func writeWav(_ capture: CapturedAudio) -> URL? {
        let url = Locator.tempDir.appendingPathComponent("rec-\(UUID().uuidString).wav")
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = Int(capture.sampleRate) * blockAlign
        let dataSize = capture.samples.count * 2

        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendU32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendU16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: Array("RIFF".utf8))
        appendU32(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        appendU32(16)
        appendU16(1)
        appendU16(UInt16(channels))
        appendU32(UInt32(capture.sampleRate))
        appendU32(UInt32(byteRate))
        appendU16(UInt16(blockAlign))
        appendU16(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataSize))

        var pcm = Data(capacity: dataSize)
        for sample in capture.samples {
            let clamped = max(-1, min(1, sample))
            var value = UInt16(bitPattern: Int16(clamped * 32_767)).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        data.append(pcm)

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
