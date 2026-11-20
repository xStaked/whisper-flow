import Foundation

/// Instant, deterministic cleanup. No model, no download, no latency.
///
/// It will not rewrite a sentence like an LLM does, but it reliably kills
/// fillers and fixes the spacing/capitalisation mess that raw dictation has.
enum RulesCleaner {

    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }

        // Fillers that never carry meaning in dictation. Deliberately conservative:
        // words like "pues", "este" or "o sea" are left alone because removing them
        // can break a real sentence.
        let fillers = ["ehh", "ehhh", "eh", "emm", "em", "umm", "um", "mmm", "hmm", "mmmh"]
        for filler in fillers {
            let pattern = "(?i)(^|[\\s,;])\\Q\(filler)\\E(?=[\\s,.!?;:]|$)"
            text = text.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
        }

        // Collapse the double spaces fillers leave behind.
        text = text.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)

        // Punctuation spacing.
        text = text.replacingOccurrences(of: "\\s+([,.;:!?])", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "([,;:])(?=[^\\s,;:])", with: "$1 ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\.{2,}", with: "…", options: .regularExpression)

        text = capitalizeSentences(text)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // A dictation is a sentence: make sure it ends like one.
        if let last = text.last, !".!?…:)".contains(last) {
            text += "."
        }

        // Never return a bare punctuation mark.
        if text.rangeOfCharacter(from: CharacterSet.alphanumerics) == nil { return "" }
        return text
    }

    private static func capitalizeSentences(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var capitalizeNext = true

        for character in text {
            if capitalizeNext, character.isLetter {
                result.append(contentsOf: character.uppercased())
                capitalizeNext = false
                continue
            }
            result.append(character)

            // New sentence after terminators; "¿" and "¡" also start one.
            if ".!?…".contains(character) {
                capitalizeNext = true
            } else if "¿¡".contains(character) {
                capitalizeNext = true
            } else if !character.isWhitespace {
                capitalizeNext = false
            }
        }
        return result
    }
}
