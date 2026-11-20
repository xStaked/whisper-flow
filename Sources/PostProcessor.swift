import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional cleanup pass with the on-device Apple Intelligence model.
///
/// Whisper gives you the words; this removes the "ehhh… o sea…" and fixes
/// punctuation. Everything stays on the machine and nothing is downloaded.
///
/// It is deliberately defensive: if the model is unavailable, slow, or returns
/// something suspiciously different from the transcript, the raw text wins.
enum PostProcessor {

    static var isAvailable: Bool {
        guard #available(macOS 26.0, *) else { return false }
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
        #else
        return false
        #endif
    }

    static var statusDescription: String {
        guard #available(macOS 26.0, *) else { return "macOS < 26" }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return "disponible"
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "dispositivo no compatible"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence desactivada"
            case .modelNotReady: return "modelo aún descargándose"
            @unknown default: return "no disponible"
            }
        @unknown default:
            return "no disponible"
        }
        #else
        return "framework ausente"
        #endif
    }

    /// Tries Apple's on-device model first, then llama.cpp. Returns nil when no
    /// backend can do the job, in which case the caller keeps the raw transcript.
    static func clean(_ raw: String, config: AppConfig) -> String? {
        guard !raw.isEmpty else { return nil }

        if let cleaned = appleClean(raw) { return cleaned }

        let engine = LlamaEngine(binaryPath: config.llmBinaryPath, modelPath: config.llmModelPath)
        guard engine.isReady else {
            Diagnostics.log("llm: sin backend (Apple: \(statusDescription); llama: no instalado)")
            return nil
        }

        let started = Date()
        do {
            let cleaned = try engine.clean(raw)
            Diagnostics.log("llm: llama.cpp respondió en \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return sanitize(cleaned, original: raw)
        } catch {
            Diagnostics.log("llm: llama falló — \(error.localizedDescription)")
            return nil
        }
    }

    /// Apple Intelligence path (only on macOS 26+ with the model enabled).
    private static func appleClean(_ raw: String) -> String? {
        if #available(macOS 26.0, *) {
            return cleanBlocking(raw, timeout: 25)
        }
        return nil
    }

    @available(macOS 26.0, *)
    private static func cleanBlocking(_ raw: String, timeout: TimeInterval) -> String? {
        guard isAvailable else { return nil }

        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        let started = Date()

        Task {
            output = await cleanAsync(raw)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            Diagnostics.log("llm: timeout tras \(Int(timeout))s")
            return nil
        }

        let elapsed = Date().timeIntervalSince(started)
        Diagnostics.log("llm: respondió en \(String(format: "%.1f", elapsed))s")
        return output
    }

    @available(macOS 26.0, *)
    private static func cleanAsync(_ raw: String) async -> String? {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            Diagnostics.log("llm: modelo no disponible (\(statusDescription))")
            return nil
        }

        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.2, maximumResponseTokens: 900)

        do {
            let response = try await session.respond(to: raw, options: options)
            return sanitize(response.content, original: raw)
        } catch {
            Diagnostics.log("llm: error \(error.localizedDescription)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private static let instructions = """
    Eres un posprocesador de dictado por voz. Recibes una transcripción cruda y \
    devuelves exactamente el mismo contenido, pero limpio:

    - Corrige puntuación, mayúsculas y espacios.
    - Quita muletillas y titubeos ("eh", "um", "ehh", "este", "o sea", "pues" \
    cuando no aportan significado) y repeticiones accidentales.
    - Separa en párrafos u oraciones cuando el texto sea largo.
    - NO traduzcas. NO resumas. NO agregues información nueva. NO cambies el \
    orden de las ideas ni el vocabulario técnico. NO respondas a lo que dice el texto.
    - Mantén el idioma original (puede venir mezclado español/inglés).

    Devuelve únicamente el texto final: sin comillas, sin prefacios, sin explicaciones.
    """

    /// Rejects obvious model failures (refusals, chit-chat, truncation).
    private static func sanitize(_ candidate: String, original: String) -> String? {
        var text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip code fences or wrapping quotes the model likes to add.
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for pair in [("\"", "\""), ("«", "»"), ("“", "”")] where text.hasPrefix(pair.0) && text.hasSuffix(pair.1) && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Drop a leading "Aquí está el texto limpio:" style preamble.
        let preambles = ["aquí está el texto", "texto limpio:", "texto corregido:", "here is the"]
        let lowercase = text.lowercased()
        for preamble in preambles where lowercase.hasPrefix(preamble) {
            if let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            break
        }

        let originalWords = original.split(whereSeparator: { $0.isWhitespace }).count
        let cleanedWords = text.split(whereSeparator: { $0.isWhitespace }).count

        guard !text.isEmpty else {
            Diagnostics.log("llm: salida vacía, uso texto crudo")
            return nil
        }
        if originalWords > 4 {
            // A cleanup can shrink text, but not by more than half, and it must
            // never grow much — both cases mean the model invented or dropped content.
            guard Double(cleanedWords) >= Double(originalWords) * 0.5,
                  Double(cleanedWords) <= Double(originalWords) * 1.8 else {
                Diagnostics.log("llm: descartado (\(originalWords) -> \(cleanedWords) palabras), uso texto crudo")
                return nil
            }
        }
        return text
    }
}
