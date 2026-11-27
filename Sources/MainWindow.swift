import AppKit

/// The main application window: sidebar, header with stats, and the dictation
/// list grouped by day — the layout Wispr Flow uses, minus the cloud features.
final class MainWindowController: NSObject {
    private var window: NSWindow?
    private var sidebarStack: NSStackView?
    private var sidebarItems: [SidebarItemView] = []

    private var greetingLabel: NSTextField?
    private var statsStack: NSStackView?
    private var wordsStatValue: NSTextField?
    private var wpmStatValue: NSTextField?
    private var daysStatValue: NSTextField?
    private var contentScroll: NSScrollView?
    private var contentStack: NSStackView?
    private var emptyState: NSView?
    private var searchField: NSSearchField?
    private var searchTerm: String = ""

    private var store: TranscriptStore?
    private var transcriber: Transcriber?
    private var currentSection = "home"

    func present(store: TranscriptStore, transcriber: Transcriber?, section: String? = nil) {
        self.store = store
        self.transcriber = transcriber
        if let section { currentSection = section }

        ensureWindow()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshIfVisible() {
        guard let window, window.isVisible else { return }
        refresh()
    }

    func hide() {
        window?.orderOut(nil)
    }

    // MARK: - Window

    private func ensureWindow() {
        guard window == nil else { return }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperFlow"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Theme.pageBackground
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.pageBackground.cgColor

        // Sidebar
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = Theme.sidebarBackground.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let logoRow = makeLogoRow()
        sidebar.addSubview(logoRow)

        let sidebarStack = NSStackView()
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 2
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        let footerLabel = NSTextField(labelWithString: "Hold fn and speak")
        footerLabel.font = Theme.caption(10.5)
        footerLabel.textColor = Theme.tertiaryText
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(footerLabel)

        // Content
        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false

        let greeting = NSTextField(labelWithString: "Your dictations")
        greeting.font = Theme.title(24)
        greeting.textColor = Theme.primaryText
        greeting.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(labelWithString: "")
        subtitle.font = Theme.body(12)
        subtitle.textColor = Theme.secondaryText
        subtitle.translatesAutoresizingMaskIntoConstraints = false

        let search = NSSearchField()
        search.placeholderString = "Search dictations"
        search.translatesAutoresizingMaskIntoConstraints = false
        search.target = self
        search.action = #selector(searchChanged)
        search.sendsSearchStringImmediately = true

        let stats = NSStackView()
        stats.orientation = .horizontal
        stats.spacing = 12
        stats.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 18, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = stack

        let empty = Self.makeEmptyState()
        empty.isHidden = true
        content.addSubview(empty)

        content.addSubview(greeting)
        content.addSubview(subtitle)
        content.addSubview(search)
        content.addSubview(stats)
        content.addSubview(scroll)

        root.addSubview(sidebar)
        root.addSubview(content)
        window.contentView = root

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Theme.sidebarWidth),

            logoRow.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 16),
            logoRow.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            logoRow.trailingAnchor.constraint(lessThanOrEqualTo: sidebar.trailingAnchor, constant: -12),

            sidebarStack.topAnchor.constraint(equalTo: logoRow.bottomAnchor, constant: 20),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),

            footerLabel.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            footerLabel.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -14),

            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            greeting.topAnchor.constraint(equalTo: content.topAnchor, constant: 44),
            greeting.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Theme.contentPadding),

            subtitle.topAnchor.constraint(equalTo: greeting.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: greeting.leadingAnchor),

            search.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            search.leadingAnchor.constraint(equalTo: greeting.leadingAnchor),
            search.widthAnchor.constraint(equalToConstant: 260),

            stats.centerYAnchor.constraint(equalTo: search.centerYAnchor),
            stats.leadingAnchor.constraint(equalTo: search.trailingAnchor, constant: 16),
            stats.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -Theme.contentPadding),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Theme.contentPadding - 6),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Theme.contentPadding),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor, constant: -14),
        ])

        // Sidebar items
        for (id, title, symbol) in [
            ("home", "Home", "square.grid.2x2"),
            ("insights", "Insights", "chart.bar"),
            ("dictionary", "Dictionary", "book"),
            ("settings", "Settings", "gearshape"),
        ] {
            let item = SidebarItemView(identifier: id, title: title, symbol: symbol)
            item.onClick { [weak self] in self?.selectSection(id) }
            sidebarStack.addArrangedSubview(item)
            sidebarItems.append(item)
        }

        self.window = window
        self.sidebarStack = sidebarStack
        self.greetingLabel = greeting
        self.contentScroll = scroll
        self.contentStack = stack
        self.emptyState = empty
        self.searchField = search
        self.statsStack = stats
    }

    private func makeLogoRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)
        icon.contentTintColor = Theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "WhisperFlow")
        name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.textColor = Theme.primaryText
        name.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(name)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            name.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            name.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            container.heightAnchor.constraint(equalToConstant: 22),
        ])
        return container
    }

    // MARK: - Content

    private func selectSection(_ id: String) {
        currentSection = id
        sidebarItems.forEach { $0.setSelected($0.sectionID == id) }
        refresh()
    }

    private func refresh() {
        guard let store, let stack = contentStack else { return }
        sidebarItems.forEach { $0.setSelected($0.sectionID == currentSection) }

        // Stats
        let words = store.entries.reduce(0) { $0 + $1.text.split(whereSeparator: { $0.isWhitespace }).count }
        let days = Set(store.entries.map { Calendar.current.startOfDay(for: $0.date) }).count
        let avgWords = store.entries.isEmpty ? 0 : words / max(1, store.entries.count)

        if statsStack != nil {
            statsStack?.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }

        if currentSection == "home" || currentSection == "insights" {
            if let statsStack {
                statsStack.addArrangedSubview(makeStat(value: "\(words)", label: "words"))
                statsStack.addArrangedSubview(makeStat(value: "\(store.entries.count)", label: "dictations"))
                statsStack.addArrangedSubview(makeStat(value: "\(avgWords)", label: "words/dict."))
                statsStack.addArrangedSubview(makeStat(value: "\(days)", label: "active days"))
            }
        }

        // Title per section
        switch currentSection {
        case "home":
            greetingLabel?.stringValue = timeGreeting()
        case "insights":
            greetingLabel?.stringValue = "Your numbers"
        case "dictionary":
            greetingLabel?.stringValue = "Words you use"
        case "settings":
            greetingLabel?.stringValue = "Settings"
        default:
            greetingLabel?.stringValue = "Your dictations"
        }

        // Rows
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch currentSection {
        case "settings":
            buildSettings(into: stack)
            emptyState?.isHidden = true
            return
        case "dictionary":
            buildDictionary(into: stack, store: store)
            emptyState?.isHidden = true
            return
        default:
            break
        }

        let filtered = store.entries.filter { entry in
            searchTerm.isEmpty || entry.text.localizedCaseInsensitiveContains(searchTerm)
        }

        if filtered.isEmpty {
            emptyState?.isHidden = false
            return
        }
        emptyState?.isHidden = true

        let grouped = groupByDay(filtered)
        for (day, entries) in grouped {
            let header = NSTextField(labelWithString: day.uppercased())
            header.font = Theme.caption(10.5)
            header.textColor = Theme.tertiaryText
            header.translatesAutoresizingMaskIntoConstraints = false
            // Space belongs to whatever was already in the stack, not to this header.
            if let last = stack.arrangedSubviews.last {
                stack.setCustomSpacing(18, after: last)
            }
            stack.addArrangedSubview(header)

            for entry in entries {
                let card = DictationCardView(entry: entry)
                card.translatesAutoresizingMaskIntoConstraints = false
                card.onCopy { [weak self] in self?.window?.makeFirstResponder(nil) }
                stack.addArrangedSubview(card)
                card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
    }

    private func makeStat(value: String, label: String) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.backgroundColor = Theme.cardBackground.cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.tertiaryText.withAlphaComponent(0.18).cgColor

        let valueLabel = NSTextField(labelWithString: value)
        valueLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        valueLabel.textColor = Theme.primaryText
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: label)
        nameLabel.font = Theme.caption(10)
        nameLabel.textColor = Theme.secondaryText
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        card.addSubview(valueLabel)
        card.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            valueLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

            nameLabel.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 1),
            nameLabel.leadingAnchor.constraint(equalTo: valueLabel.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            nameLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),
        ])
        return card
    }

    private func buildDictionary(into stack: NSStackView, store: TranscriptStore) {
        // Filler and stop words: they add nothing to a personal "dictionary".
        let stopWords: Set<String> = [
            "de", "la", "el", "que", "y", "en", "un", "a", "los", "se", "no", "con", "es",
            "por", "para", "lo", "una", "me", "si", "mi", "pero", "como", "porque", "pues",
            "entonces", "este", "esta", "esto", "esa", "eso", "muy", "mas", "más", "ya",
            "tambien", "también", "cuando", "donde", "hay", "tiene", "tener", "hacer",
            "bueno", "bien", "mucho", "muchos", "todo", "todos", "hacia", "desde", "sobre",
            "entre", "cuando", "mientras", "solo", "sólo", "aquí", "ahi", "ahí", "puedo",
            "puede", "estoy", "esta", "está", "estan", "están", "ser", "son", "fue", "era",
            "the", "and", "to", "of", "in", "is", "it", "you", "that", "this", "for", "with",
        ]

        var counts: [String: Int] = [:]
        for entry in store.entries {
            for word in entry.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let token = String(word)
                guard token.count > 3, !stopWords.contains(token) else { continue }
                counts[token, default: 0] += 1
            }
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(30)

        guard !top.isEmpty else {
            let hint = NSTextField(wrappingLabelWithString: "Dictate something and the words you use most show up here.")
            hint.font = Theme.body(12)
            hint.textColor = Theme.secondaryText
            stack.addArrangedSubview(hint)
            return
        }

        for (index, item) in top.enumerated() {
            let row = NSView()
            row.translatesAutoresizingMaskIntoConstraints = false

            let rank = NSTextField(labelWithString: "\(index + 1)")
            rank.font = Theme.caption(10)
            rank.textColor = Theme.tertiaryText
            rank.translatesAutoresizingMaskIntoConstraints = false

            let word = NSTextField(labelWithString: item.key)
            word.font = .systemFont(ofSize: 13, weight: .medium)
            word.textColor = Theme.primaryText
            word.translatesAutoresizingMaskIntoConstraints = false

            let count = NSTextField(labelWithString: "\(item.value)×")
            count.font = Theme.caption(10.5)
            count.textColor = Theme.secondaryText
            count.translatesAutoresizingMaskIntoConstraints = false

            row.addSubview(rank)
            row.addSubview(word)
            row.addSubview(count)

            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 28),
                rank.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 4),
                rank.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                word.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 32),
                word.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                count.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                count.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            stack.addArrangedSubview(row)
        }
    }

    private func buildSettings(into stack: NSStackView) {
        let hint = NSTextField(wrappingLabelWithString: """
        The real settings live in:
        ~/Library/Application Support/WhisperFlow/config.json

        Language, speech model, text cleanup and sounds are changed there.
        Right click the menu icon → Open data folder.
        """)
        hint.font = Theme.body(12)
        hint.textColor = Theme.secondaryText
        stack.addArrangedSubview(hint)
    }

    private func groupByDay(_ entries: [TranscriptEntry]) -> [(String, [TranscriptEntry])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d 'de' MMMM, yyyy"

        var order: [Date] = []
        var groups: [Date: [TranscriptEntry]] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(entry)
        }

        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        return order.map { day in
            let label: String
            if day == today {
                label = "Today"
            } else if day == yesterday {
                label = "Yesterday"
            } else {
                label = formatter.string(from: day)
            }
            return (label, groups[day] ?? [])
        }
    }

    private func timeGreeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<12: return "Good morning"
        case 12..<19: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private static func makeEmptyState() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "mic.circle", accessibilityDescription: nil)
        icon.contentTintColor = Theme.tertiaryText
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Your first dictation")
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.textColor = Theme.secondaryText
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(wrappingLabelWithString:
            "Hold the fn key, speak naturally and release.\nThe text appears wherever your cursor is.")
        hint.font = Theme.body(12)
        hint.textColor = Theme.tertiaryText
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(hint)

        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: container.topAnchor),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),

            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            hint.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            hint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.widthAnchor.constraint(equalToConstant: 360),
        ])
        return container
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchTerm = sender.stringValue
        refresh()
    }
}
