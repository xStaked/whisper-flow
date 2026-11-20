import Foundation

enum LlamaError: LocalizedError {
    case notReady
    case failed(Int32, String)
    case timedOut
    case unusableOutput

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "llama.cpp o el modelo no están instalados."
        case .failed(let code, let detail):
            return "llama falló (\(code)): \(detail)"
        case .timedOut:
            return "El modelo tardó demasiado."
        case .unusableOutput:
            return "La salida del modelo no era usable."
        }
    }
}

/// Local text cleanup through llama.cpp (Metal = GPU on Apple Silicon).
///
/// Used when Apple Intelligence is not available, which is the common case in
/// regions where it has not shipped. Costs ~4-5 s per dictation because the
/// model is loaded per call — that is the price of keeping 0 MB resident.
struct LlamaEngine {
    let binaryPath: String
    let modelPath: String

    var isReady: Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
            && FileManager.default.fileExists(atPath: modelPath)
    }

    func clean(_ text: String, timeout: TimeInterval = 45) throws -> String {
        guard isReady else { throw LlamaError.notReady }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "-m", modelPath,
            "-p", Self.chatPrompt(for: text),
            "-c", "4096",
            "-n", "600",
            "--temp", "0.2",
            "--no-display-prompt",
        ]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }

        if process.isRunning {
            Diagnostics.log("llm: llama sin respuesta tras \(Int(timeout))s")
            process.terminate()
            usleep(400_000)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw LlamaError.timedOut
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let detail = stderr.split(separator: "\n").suffix(2).joined(separator: " ")
            throw LlamaError.failed(process.terminationStatus, detail)
        }

        guard let cleaned = Self.parse(stdout) else { throw LlamaError.unusableOutput }
        return cleaned
    }

    // MARK: - Prompt

    /// Qwen/ChatML template. Feeding the template ourselves (instead of letting
    /// llama-cli run its interactive chat loop) keeps stdout to the answer alone.
    static func chatPrompt(for text: String) -> String {
        """
        <|im_start|>system
        \(systemPrompt)<|im_end|>
        <|im_start|>user
        \(text)<|im_end|>
        <|im_start|>assistant

        """
    }

    // MARK: - Parsing

    static func parse(_ raw: String) -> String? {
        var text = raw

        // Completion mode appends a sentinel and may echo a "> " prompt prefix.
        if let range = text.range(of: "> EOF by user") {
            text = String(text[..<range.lowerBound])
        }
        if let range = text.range(of: "<|im_end|>") {
            text = String(text[..<range.lowerBound])
        }
        if let range = text.range(of: "<|im_start|>assistant", options: .backwards) {
            text = String(text[range.upperBound...])
        }

        text = text.replacingOccurrences(
            of: "\u{001B}\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text.isEmpty ? nil : text
    }

    private static let systemPrompt = """
    Eres un posprocesador de dictado por voz. Recibes una transcripción cruda en \
    español, inglés o mezcla, y devuelves el mismo contenido limpio:
    - Corrige puntuación, mayúsculas y espacios.
    - Quita muletillas y titubeos (eh, um, este, o sea, pues) y repeticiones.
    - NO traduzcas, NO resumas, NO agregues datos, NO respondas a lo que dice el texto.
    - Devuelve solo el texto final, sin comillas ni explicaciones.
    """
}
