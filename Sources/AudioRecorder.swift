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

/// Captures the microphone into memory and writes a plain 16-bit WAV when
/// recording stops. Samples are collected as Float32 and downmixed to mono.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 48_000
    private var tapInstalled = false
    private var autoStopWork: DispatchWorkItem?

    private(set) var isRecording = false
    var onAutoStop: (() -> Void)?

    static var permissionGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            throw error
        }

        isRecording = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isRecording else { return }
            self.onAutoStop?()
        }
        autoStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + maxSeconds, execute: work)
    }

    /// Stops recording and returns the WAV file, or nil when nothing was captured.
    func stop() -> URL? {
        guard isRecording else { return nil }
        autoStopWork?.cancel()
        autoStopWork = nil
        teardown()

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        guard !captured.isEmpty else { return nil }
        return Self.writeWav(samples: captured, sampleRate: sampleRate)
    }

    func cancel() {
        autoStopWork?.cancel()
        autoStopWork = nil
        if isRecording { teardown() }
        lock.lock()
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func teardown() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
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

    private static func writeWav(samples: [Float], sampleRate: Double) -> URL? {
        let url = Locator.tempDir.appendingPathComponent("rec-\(UUID().uuidString).wav")
        let channels = 1
        let bitsPerSample = 16
        let blockAlign = channels * bitsPerSample / 8
        let byteRate = Int(sampleRate) * blockAlign
        let dataSize = samples.count * 2

        var data = Data()
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
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(byteRate))
        appendU16(UInt16(blockAlign))
        appendU16(UInt16(bitsPerSample))
        data.append(contentsOf: Array("data".utf8))
        appendU32(UInt32(dataSize))

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            appendU16(UInt16(bitPattern: Int16(clamped * 32_767)))
        }

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
