import SwiftUI

/// Maps a usage fraction (0...1) to a status color, tuned for dark/light and an
/// optional colorblind-safe palette. green ≤50% → yellow ≤75% → orange ≤90% → red.
enum ThresholdColor {

    static func color(for fraction: Double, colorblind: Bool = false) -> Color {
        let f = max(0, min(1, fraction))
        if colorblind {
            // Blue → teal → amber → magenta ramp (distinguishable for common CVD).
            switch f {
            case ..<0.5:  return Color(red: 0.20, green: 0.55, blue: 0.95)
            case ..<0.75: return Color(red: 0.10, green: 0.70, blue: 0.70)
            case ..<0.90: return Color(red: 0.95, green: 0.70, blue: 0.15)
            default:      return Color(red: 0.85, green: 0.20, blue: 0.70)
            }
        }
        // Breakpoints + shades tuned to the mockup: 21% green, 52% yellow, 73% orange-red.
        switch f {
        case ..<0.35: return Color(red: 0.22, green: 0.80, blue: 0.45) // green
        case ..<0.70: return Color(red: 0.92, green: 0.82, blue: 0.15) // yellow
        case ..<0.85: return Color(red: 0.96, green: 0.30, blue: 0.12) // orange-red
        default:      return Color(red: 0.86, green: 0.16, blue: 0.14) // red
        }
    }
}
