import SwiftUI

/// User-selectable appearance mode. Persisted in UserDefaults.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Semantic color tokens. Views read these instead of hard-coded colors so both
/// themes stay consistent across the popover and the notch rail.
enum Theme {
    static let cardBackground = Color("CardBackground", bundle: nil, fallbackLight: Color(white: 0.97), fallbackDark: Color(white: 0.08))
    static let popoverBackground = Color("PopoverBackground", bundle: nil, fallbackLight: .white, fallbackDark: Color(white: 0.10))
    static let textPrimary = Color("TextPrimary", bundle: nil, fallbackLight: Color(white: 0.10), fallbackDark: Color(white: 0.96))
    static let textSecondary = Color("TextSecondary", bundle: nil, fallbackLight: Color(white: 0.45), fallbackDark: Color(white: 0.60))
    static let track = Color("Track", bundle: nil, fallbackLight: Color(white: 0.88), fallbackDark: Color(white: 0.22))
}

extension Color {
    /// Convenience initializer that resolves a named asset color when available,
    /// otherwise falls back to explicit light/dark values (works without an asset catalog).
    init(_ name: String, bundle: Bundle?, fallbackLight: Color, fallbackDark: Color) {
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? fallbackDark : fallbackLight)
        })
    }
}
