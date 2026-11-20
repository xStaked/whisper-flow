import Foundation

enum TranscriberError: LocalizedError {
    case missingBinary(String)
    case missingModel(String)
    case ffmpegFailed(String)
    case whisperFailed(Int32, String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .missingBinary(let path):
            return "No encuentro whisper-cli en \(path.isEmpty ? "(ruta vacía)" : path). Compila con ./build.sh o edita config.json."
        case .missingModel(let path):
            return "No encuentro el modelo en \(path.isEmpty ? "(ruta vacía)" : path). Descárgalo con ./download-model.sh."
        case .ffmpegFailed(let detail):
            return "ffmpeg falló: \(detail)"
        case .whisperFailed(let code, let detail):
            return "whisper-cli falló (código \(code)): \(detail)"
        case .emptyResult:
            return "No se entendió nada en el audio."
        }
    }
}

/// Runs the local pipeline: WAV capture → ffmpeg (16 kHz mono) → whisper-cli → text.
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
            throw TranscriberError.whisperFailed(0, "no se generó el archivo de texto")
        }
        let text = Self.clean(raw)
        guard !text.isEmpty else { throw TranscriberError.emptyResult }
        return text
    }

    private func resample(input: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.ffmpegPath)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y",
                             "-i", input.path,
                             "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le",
                             output.path]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "error desconocido"
            throw TranscriberError.ffmpegFailed(detail.isEmpty ? "error desconocido" : detail)
        }
    }

    private func runWhisper(args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.whisperBinaryPath)
        process.arguments = args
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        try process.run()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "error desconocido"
            throw TranscriberError.whisperFailed(process.terminationStatus, detail)
        }
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
