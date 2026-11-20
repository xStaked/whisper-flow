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

    private(set) var isRecording = false
    var onAutoStop: (() -> Void)?

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
            Diagnostics.log("audio: cambió el dispositivo, cerrando grabación")
            self.onAutoStop?()
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

        lock.lock()
        samples.append(contentsOf: mono)
        lock.unlock()
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
