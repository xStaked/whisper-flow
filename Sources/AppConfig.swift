import Foundation

/// Everything tunable lives here. It is written to
/// ~/Library/Application Support/WhisperFlow/config.json on first launch
/// so the user can edit it without touching the app bundle.
struct AppConfig: Codable {
    var language: String
    var modelPath: String
    var whisperBinaryPath: String
    var ffmpegPath: String
    var maxRecordSeconds: Double
    var soundsEnabled: Bool
    var autoInsert: Bool
    var postProcess: Bool
    var postProcessEngine: String
    var llmBinaryPath: String
    var llmModelPath: String
    var postProcessMinWords: Int

    static let fallback = AppConfig(
        language: "auto",
        modelPath: "",
        whisperBinaryPath: "",
        ffmpegPath: "/opt/homebrew/bin/ffmpeg",
        maxRecordSeconds: 120,
        soundsEnabled: true,
        autoInsert: true,
        postProcess: false,
        postProcessEngine: "rules",
        llmBinaryPath: "",
        llmModelPath: "",
        postProcessMinWords: 12
    )

    init(language: String,
         modelPath: String,
         whisperBinaryPath: String,
         ffmpegPath: String,
         maxRecordSeconds: Double,
         soundsEnabled: Bool,
         autoInsert: Bool,
         postProcess: Bool,
         postProcessEngine: String,
         llmBinaryPath: String,
         llmModelPath: String,
         postProcessMinWords: Int) {
        self.language = language
        self.modelPath = modelPath
        self.whisperBinaryPath = whisperBinaryPath
        self.ffmpegPath = ffmpegPath
        self.maxRecordSeconds = maxRecordSeconds
        self.soundsEnabled = soundsEnabled
        self.autoInsert = autoInsert
        self.postProcess = postProcess
        self.postProcessEngine = postProcessEngine
        self.llmBinaryPath = llmBinaryPath
        self.llmModelPath = llmModelPath
        self.postProcessMinWords = postProcessMinWords
    }

    // Tolerant decoding: a hand-edited config with a missing key must not crash the app.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = AppConfig.fallback
        language = (try? c.decode(String.self, forKey: .language)) ?? f.language
        modelPath = (try? c.decode(String.self, forKey: .modelPath)) ?? f.modelPath
        whisperBinaryPath = (try? c.decode(String.self, forKey: .whisperBinaryPath)) ?? f.whisperBinaryPath
        ffmpegPath = (try? c.decode(String.self, forKey: .ffmpegPath)) ?? f.ffmpegPath
        maxRecordSeconds = (try? c.decode(Double.self, forKey: .maxRecordSeconds)) ?? f.maxRecordSeconds
        soundsEnabled = (try? c.decode(Bool.self, forKey: .soundsEnabled)) ?? f.soundsEnabled
        autoInsert = (try? c.decode(Bool.self, forKey: .autoInsert)) ?? f.autoInsert
        postProcess = (try? c.decode(Bool.self, forKey: .postProcess)) ?? f.postProcess
        postProcessEngine = (try? c.decode(String.self, forKey: .postProcessEngine)) ?? f.postProcessEngine
        llmBinaryPath = (try? c.decode(String.self, forKey: .llmBinaryPath)) ?? f.llmBinaryPath
        llmModelPath = (try? c.decode(String.self, forKey: .llmModelPath)) ?? f.llmModelPath
        postProcessMinWords = (try? c.decode(Int.self, forKey: .postProcessMinWords)) ?? f.postProcessMinWords
    }
}

/// Finds the app support folder, the model and the binaries no matter where
/// the .app happens to sit.
enum Locator {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("WhisperFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL { supportDir.appendingPathComponent("config.json") }
    static var historyURL: URL { supportDir.appendingPathComponent("history.json") }

    static var tempDir: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WhisperFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadOrDefault() -> AppConfig {
        var cfg = read(configURL) ?? bundleDefaultsURL.flatMap(read) ?? AppConfig.fallback
        resolve(&cfg)
        return cfg
    }

    static func save(_ cfg: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(cfg) else { return }
        try? data.write(to: configURL)
    }

    private static var bundleDefaultsURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("runtime-defaults.json")
    }

    private static func read(_ url: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    /// Root folder that contains `models/` and `vendor-whisper/` — either the
    /// source checkout or the folder holding the .app.
    private static var searchRoots: [URL] {
        let bundle = Bundle.main.bundleURL
        // <root>/build/WhisperFlow.app -> <root>
        var roots: [URL] = [
            bundle,
            bundle.deletingLastPathComponent(),
            bundle.deletingLastPathComponent().deletingLastPathComponent(),
            bundle.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent(),
        ]
        roots.append(supportDir)
        roots.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("whisper.cpp"))
        roots.append(URL(fileURLWithPath: "/opt/homebrew/share/whisper-cpp"))
        roots.append(URL(fileURLWithPath: "/usr/local/share/whisper-cpp"))
        return roots
    }

    private static func resolve(_ cfg: inout AppConfig) {
        if cfg.ffmpegPath.isEmpty || !FileManager.default.isExecutableFile(atPath: cfg.ffmpegPath) {
            let candidates = ["/opt/homebrew/bin/ffmpeg",
                              "/usr/local/bin/ffmpeg",
                              "/usr/bin/ffmpeg"]
            if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                cfg.ffmpegPath = hit
            }
        }

        if cfg.whisperBinaryPath.isEmpty || !FileManager.default.isExecutableFile(atPath: cfg.whisperBinaryPath) {
            let names = ["whisper-cli", "main", "whisper"]
            let dirs = ["", "build/bin", "bin", "vendor-whisper/build/bin", "vendor-whisper"]
            outer: for root in searchRoots {
                for sub in dirs {
                    for name in names {
                        let candidate = sub.isEmpty
                            ? root.appendingPathComponent(name)
                            : root.appendingPathComponent(sub).appendingPathComponent(name)
                        if FileManager.default.isExecutableFile(atPath: candidate.path) {
                            cfg.whisperBinaryPath = candidate.path
                            break outer
                        }
                    }
                }
            }
            if cfg.whisperBinaryPath.isEmpty {
                for path in ["/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli"] {
                    if FileManager.default.isExecutableFile(atPath: path) {
                        cfg.whisperBinaryPath = path
                        break
                    }
                }
            }
        }

        if cfg.modelPath.isEmpty || !FileManager.default.fileExists(atPath: cfg.modelPath) {
            cfg.modelPath = findModel() ?? ""
        }

        if cfg.llmBinaryPath.isEmpty || !FileManager.default.isExecutableFile(atPath: cfg.llmBinaryPath) {
            cfg.llmBinaryPath = findLlamaBinary() ?? ""
        }

        if cfg.llmModelPath.isEmpty || !FileManager.default.fileExists(atPath: cfg.llmModelPath) {
            cfg.llmModelPath = findLlamaModel() ?? ""
        }
    }

    private static func findLlamaBinary() -> String? {
        let fm = FileManager.default
        for root in searchRoots {
            for name in ["llama-completion", "llama-cli"] {
                let direct = [root.appendingPathComponent(name),
                              root.appendingPathComponent("vendor-llama/\(name)"),
                              root.appendingPathComponent("Resources/\(name)")]
                for candidate in direct where fm.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
            // vendor-llama/llama-<build>/llama-cli
            let vendor = root.appendingPathComponent("vendor-llama")
            let entries = (try? fm.contentsOfDirectory(atPath: vendor.path)) ?? []
            for entry in entries.sorted(by: >) {
                for name in ["llama-completion", "llama-cli"] {
                    let candidate = vendor.appendingPathComponent(entry).appendingPathComponent(name)
                    if fm.isExecutableFile(atPath: candidate.path) { return candidate.path }
                }
            }
        }
        return nil
    }

    private static func findLlamaModel() -> String? {
        let fm = FileManager.default
        var candidates: [URL] = []
        for root in searchRoots {
            candidates.append(root.appendingPathComponent("models"))
        }
        for dir in candidates {
            let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            let ggufs = files.filter { $0.lowercased().hasSuffix(".gguf") }
            if let instruct = ggufs.first(where: { $0.lowercased().contains("instruct") }) {
                return dir.appendingPathComponent(instruct).path
            }
            if let any = ggufs.first { return dir.appendingPathComponent(any).path }
        }
        return nil
    }

    private static func findModel() -> String? {
        let fm = FileManager.default
        var dirs: [URL] = []
        for root in searchRoots {
            dirs.append(root)
            dirs.append(root.appendingPathComponent("models"))
            dirs.append(root.appendingPathComponent("Resources"))
            dirs.append(root.appendingPathComponent("Contents/Resources"))
        }
        // Prefer the biggest accurate model we know about, then anything else.
        let preferred = ["ggml-large-v3-turbo-q5_0.bin",
                         "ggml-large-v3-turbo.bin",
                         "ggml-medium-q5_0.bin",
                         "ggml-small-q5_1.bin",
                         "ggml-small.bin",
                         "ggml-base.bin"]
        for name in preferred {
            for dir in dirs {
                let candidate = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) { return candidate.path }
            }
        }
        for dir in dirs {
            let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            if let match = contents.first(where: { $0.hasPrefix("ggml-") && $0.hasSuffix(".bin") }) {
                return dir.appendingPathComponent(match).path
            }
        }
        return nil
    }
}
