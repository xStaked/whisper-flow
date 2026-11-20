import Foundation

struct TranscriptEntry: Codable {
    let id: UUID
    let date: Date
    let text: String
}

/// Rolling history of the last 50 dictations, persisted as JSON so nothing is
/// lost if the app crashes or the insertion silently failed.
final class TranscriptStore {
    private(set) var entries: [TranscriptEntry] = []
    private let limit = 50

    init() {
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(TranscriptEntry(id: UUID(), date: Date(), text: trimmed), at: 0)
        if entries.count > limit {
            entries = Array(entries.prefix(limit))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Locator.historyURL),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: Locator.historyURL)
    }
}
