import Foundation

/// How a provider's numbers were obtained. Surfaced in the UI as a source badge.
enum DataSource: String, Codable, Sendable {
    case localEstimate   // parsed from local CLI files — approximate, this machine only
    case authoritative   // real numbers from an official/usage endpoint
    case manual          // user-entered cap
    case unavailable     // no data yet / not connected

    var badge: String {
        switch self {
        case .localEstimate: return "estimated"
        case .authoritative: return "live"
        case .manual: return "manual"
        case .unavailable: return "—"
        }
    }
}

/// A single usage window (e.g. the 5-hour session or the weekly cap).
struct UsageWindow: Identifiable, Hashable, Sendable {
    let id = UUID()
    var label: String            // "Current session", "All models"
    var percentUsed: Double      // 0.0 ... 1.0 (may exceed 1.0 if over cap)
    var resetsAt: Date?          // when this window resets, if known

    /// Clamped 0...1 value for drawing rings/bars.
    var fraction: Double { max(0, min(1, percentUsed)) }

    /// Human string like "73%".
    var percentText: String { "\(Int((percentUsed * 100).rounded()))%" }
}

/// The known providers. Stable ids used for persistence and Keychain keys.
enum ProviderID: String, CaseIterable, Codable, Sendable, Identifiable {
    case claude
    case openai      // ChatGPT / Codex
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    /// SF Symbol fallback glyph until custom brand glyphs are added.
    var symbolName: String {
        switch self {
        case .claude: return "sparkle"
        case .openai: return "circle.hexagongrid"
        case .gemini: return "snowflake"
        }
    }
}

/// A provider's current status, shown as a ring in the rail and a card in the popover.
struct ProviderStatus: Identifiable, Sendable {
    var id: ProviderID
    var session: UsageWindow?    // short rolling window (5h for Claude)
    var weekly: UsageWindow?     // weekly all-models cap
    var source: DataSource
    var lastUpdated: Date?
    var errorMessage: String?

    var name: String { id.displayName }

    /// The window the rail ring should visualize (session preferred, else weekly).
    var primaryWindow: UsageWindow? { session ?? weekly }

    static func empty(_ id: ProviderID) -> ProviderStatus {
        ProviderStatus(id: id, session: nil, weekly: nil,
                       source: .unavailable, lastUpdated: nil, errorMessage: nil)
    }
}

/// Which screen edge the rail is docked to (Samsung-style edge panel).
enum RailEdge: String, CaseIterable, Identifiable, Codable, Sendable {
    case left
    case right

    var id: String { rawValue }
    var label: String { self == .left ? "Left edge" : "Right edge" }
}

/// A full snapshot across all enabled providers.
struct UsageSnapshot: Sendable {
    var providers: [ProviderStatus]
    var capturedAt: Date

    func status(for id: ProviderID) -> ProviderStatus? {
        providers.first { $0.id == id }
    }
}
