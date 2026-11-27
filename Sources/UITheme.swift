import AppKit

/// Colors, fonts and metrics for the main window.
///
/// Everything is derived from system colors with explicit light/dark variants so
/// the app looks native in both modes instead of hardcoding one theme.
enum Theme {

    static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // Surfaces
    static let pageBackground = dynamic(
        NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
    )
    static let sidebarBackground = dynamic(
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.93, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.13, blue: 0.14, alpha: 1)
    )
    static let cardBackground = dynamic(
        NSColor(calibratedRed: 0.925, green: 0.91, blue: 0.885, alpha: 1),
        NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let cardHover = dynamic(
        NSColor(calibratedRed: 0.895, green: 0.875, blue: 0.845, alpha: 1),
        NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.21, alpha: 1)
    )

    // Text
    static let primaryText = dynamic(
        NSColor(calibratedWhite: 0.10, alpha: 1),
        NSColor(calibratedWhite: 0.95, alpha: 1)
    )
    static let secondaryText = dynamic(
        NSColor(calibratedWhite: 0.42, alpha: 1),
        NSColor(calibratedWhite: 0.62, alpha: 1)
    )
    static let tertiaryText = dynamic(
        NSColor(calibratedWhite: 0.60, alpha: 1),
        NSColor(calibratedWhite: 0.45, alpha: 1)
    )

    // Accent
    static let accent = dynamic(
        NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.15, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.22, alpha: 1)
    )
    static let recording = NSColor.systemRed

    // Fonts
    static func title(_ size: CGFloat = 22) -> NSFont {
        .systemFont(ofSize: size, weight: .semibold)
    }
    static func body(_ size: CGFloat = 13) -> NSFont {
        .systemFont(ofSize: size, weight: .regular)
    }
    static func caption(_ size: CGFloat = 11) -> NSFont {
        .systemFont(ofSize: size, weight: .medium)
    }

    // Metrics
    static let sidebarWidth: CGFloat = 212
    static let contentPadding: CGFloat = 32
    static let cardRadius: CGFloat = 12
    static let cardPadding: CGFloat = 18
}
