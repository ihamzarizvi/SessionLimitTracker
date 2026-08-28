import Foundation

/// A provider whose usage is entered by the user (the "Manual" connection method).
/// Fully functional and honest — badged `.manual`.
struct ManualProvider: UsageProvider {
    let id: ProviderID
    var session: UsageWindow?
    var weekly: UsageWindow?
    func fetch() async -> ProviderStatus {
        ProviderStatus(id: id, session: session, weekly: weekly, source: .manual,
                       lastUpdated: Date(), errorMessage: nil)
    }
}

/// Reports a provider's connection state when there is no live data source yet
/// (e.g. ChatGPT-Plus caps, which no official API exposes). Keeps the UI honest.
struct ConnectionStatusProvider: UsageProvider {
    let id: ProviderID
    var note: String
    func fetch() async -> ProviderStatus {
        ProviderStatus(id: id, session: nil, weekly: nil, source: .unavailable,
                       lastUpdated: Date(), errorMessage: note)
    }
}

/// Best-effort local reader for CLI tools that log sessions like Claude Code does
/// (Codex, Gemini). Scans a directory for `*.jsonl` token usage; if none is found
/// it reports unavailable rather than inventing numbers.
struct CLILocalProvider: UsageProvider {
    let id: ProviderID
    var root: URL
    var bucketer: WindowBucketer

    func fetch() async -> ProviderStatus {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ProviderStatus(id: id, session: nil, weekly: nil, source: .unavailable,
                                  lastUpdated: Date(), errorMessage: "No local \(id.displayName) CLI data found")
        }
        let events = JSONLScanner(root: root).scan()
        guard !events.isEmpty else {
            return ProviderStatus(id: id, session: nil, weekly: nil, source: .unavailable,
                                  lastUpdated: Date(), errorMessage: "No recent \(id.displayName) CLI usage")
        }
        let session = bucketer.sessionWindow(events: events)
        let weekly = bucketer.weeklyWindow(events: events)
        return ProviderStatus(id: id, session: session, weekly: weekly, source: .localEstimate,
                              lastUpdated: Date(), errorMessage: nil)
    }
}
