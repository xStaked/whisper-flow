import Foundation

/// Plain-text log in ~/Library/Application Support/WhisperFlow/whisperflow.log.
/// Used to debug the hotkey, which is otherwise invisible from the outside.
enum Diagnostics {
    private static let queue = DispatchQueue(label: "com.local.whisperflow.log")

    static var logURL: URL {
        Locator.supportDir.appendingPathComponent("whisperflow.log")
    }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let url = logURL
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    static func reset() {
        try? FileManager.default.removeItem(at: logURL)
    }
}
