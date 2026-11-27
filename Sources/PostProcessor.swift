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
            case .deviceNotEligible: return "device not eligible"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence disabled"
            case .modelNotReady: return "model still downloading"
            @unknown default: return "unavailable"
            }
        @unknown default:
            return "unavailable"
        }
        #else
        return "framework missing"
        #endif
    }

    /// Tries Apple's on-device model first, then llama.cpp. Returns nil when no
    /// backend can do the job, in which case the caller keeps the raw transcript.
    static func clean(_ raw: String, config: AppConfig) -> String? {
        guard !raw.isEmpty else { return nil }

        if let cleaned = appleClean(raw) { return cleaned }

        let engine = LlamaEngine(binaryPath: config.llmBinaryPath, modelPath: config.llmModelPath)
        guard engine.isReady else {
            Diagnostics.log("llm: no backend (Apple: \(statusDescription); llama: not installed)")
            return nil
        }

        let started = Date()
        do {
            let cleaned = try engine.clean(raw)
            Diagnostics.log("llm: llama.cpp answered in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return sanitize(cleaned, original: raw)
        } catch {
            Diagnostics.log("llm: llama failed — \(error.localizedDescription)")
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
            Diagnostics.log("llm: timeout after \(Int(timeout))s")
            return nil
        }

        let elapsed = Date().timeIntervalSince(started)
        Diagnostics.log("llm: answered in \(String(format: "%.1f", elapsed))s")
        return output
    }

    @available(macOS 26.0, *)
    private static func cleanAsync(_ raw: String) async -> String? {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            Diagnostics.log("llm: model unavailable (\(statusDescription))")
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
    You are a voice-dictation post-processor. You receive a raw transcript and \
    return exactly the same content, cleaned up:

    - Fix punctuation, capitalisation and spacing.
    - Remove filler words and stutters ("um", "uh", "like", "you know", "o sea", \
    "pues") only where they carry no meaning, and accidental repetitions.
    - Split into sentences or paragraphs when the text is long.
    - Do NOT translate. Do NOT summarise. Do NOT add new information. Do NOT \
    reorder ideas or change technical vocabulary. Do NOT answer what the text says.
    - Keep the original language (it may mix Spanish and English).

    Return only the final text: no quotes, no preamble, no explanations.
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

        // Drop a leading "Here is the cleaned text:" style preamble.
        let preambles = ["here is the", "cleaned text:", "corrected text:"]
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
            Diagnostics.log("llm: empty output, using raw text")
            return nil
        }
        if originalWords > 4 {
            // A cleanup can shrink text, but not by more than half, and it must
            // never grow much — both cases mean the model invented or dropped content.
            guard Double(cleanedWords) >= Double(originalWords) * 0.5,
                  Double(cleanedWords) <= Double(originalWords) * 1.8 else {
                Diagnostics.log("llm: rejected (\(originalWords) -> \(cleanedWords) words), using raw text")
                return nil
            }
        }
        return text
    }
}
