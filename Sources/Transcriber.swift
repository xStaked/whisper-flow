import Foundation

enum TranscriberError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case ffmpegFailed(String)
    case whisperFailed(Int32, String)
    case timedOut(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            return "Cannot find whisper-cli at \(path.isEmpty ? "(empty path)" : path). Build with ./build.sh or edit config.json."
        case .missingModel(let path):
            return "Cannot find the model at \(path.isEmpty ? "(empty path)" : path). Download it with ./download-model.sh."
        case .ffmpegFailed(let detail):
            return "ffmpeg failed: \(detail)"
        case .whisperFailed(let code, let detail):
            return "whisper-cli failed (code \(code)): \(detail)"
        case .timedOut(let label):
            return "\(label) hung and was cancelled."
        case .emptyResult:
            return "Nothing intelligible in the audio."
        }
    }
}

/// Runs the local pipeline: WAV capture → ffmpeg (16 kHz mono) → whisper-cli → text.
///
/// Every child process has a hard timeout: a stuck whisper would otherwise leave
/// the app permanently "busy" and the hotkey would stop responding forever.
final class Transcriber {
    private let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    func transcribe(recordingAt url: URL) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: config.whisperBinaryPath) else {
            throw TranscriberError.missingBinary(config.whisperBinaryPath)
        }
        guard FileManager.default.fileExists(atPath: config.modelPath) else {
            throw TranscriberError.missingModel(config.modelPath)
        }

        let base = url.deletingPathExtension()
        let wav16k = base.appendingPathExtension("16k.wav")
        defer {
            try? FileManager.default.removeItem(at: wav16k)
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: base.path + ".txt"))
        }

        try resample(input: url, output: wav16k)

        let outputBase = base.path
        var args = ["-m", config.modelPath,
                    "-f", wav16k.path,
                    "-l", config.language,
                    "-nt", "-np",
                    "-otxt",
                    "-of", outputBase]
        let threads = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2))
        args += ["-t", String(threads)]

        try runWhisper(args: args)

        guard let raw = try? String(contentsOfFile: outputBase + ".txt", encoding: .utf8) else {
            throw TranscriberError.whisperFailed(0, "no text file was produced")
        }
        let text = Self.clean(raw)
        guard !text.isEmpty else { throw TranscriberError.emptyResult }
        return text
    }

    // MARK: - Child processes

    private func resample(input: URL, output: URL) throws {
        let (status, stderr) = try run(
            path: config.ffmpegPath,
            arguments: ["-hide_banner", "-loglevel", "error", "-y",
                        "-i", input.path,
                        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                        output.path],
            label: "ffmpeg",
            timeout: 30
        )
        guard status == 0 else {
            throw TranscriberError.ffmpegFailed(stderr.isEmpty ? "error desconocido" : stderr)
        }
    }

    private func runWhisper(args: [String]) throws {
        let (status, stderr) = try run(
            path: config.whisperBinaryPath,
            arguments: args,
            label: "whisper-cli",
            timeout: 90
        )
        guard status == 0 else {
            throw TranscriberError.whisperFailed(status, stderr.isEmpty ? "error desconocido" : stderr)
        }
    }

    private func run(path: String, arguments: [String], label: String, timeout: TimeInterval) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            Diagnostics.log("\(label): no response after \(Int(timeout))s, terminating")
            process.terminate()
            usleep(500_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw TranscriberError.timedOut(label)
        }

        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stderrText)
    }

    /// Whisper hallucinates bracketed noise markers on silence; strip them out.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let noise = ["[BLANK_AUDIO]", "[blank_audio]", "[SILENCE]", "(silence)", "[silence]",
                     "[MUSIC]", "[music]", "(música)", "[MÚSICA]", "(music)", "[SOUND]",
                     "[SOUND EFFECT]", "(risas)", "[LAUGHTER]", "[NOISE]"]
        for marker in noise {
            text = text.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        if text.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil { return "" }
        return text
    }
}
