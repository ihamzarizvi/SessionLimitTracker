import Foundation

/// Default, fully-compliant Claude provider: estimates the 5-hour session and
/// weekly windows from local Claude Code transcript files. No login, offline,
/// this-machine-only. Numbers are badged `.localEstimate`.
struct ClaudeLocalProvider: UsageProvider {
    let id: ProviderID = .claude
    var scanner: JSONLScanner
    var bucketer: WindowBucketer

    init(scanner: JSONLScanner = JSONLScanner(), bucketer: WindowBucketer = WindowBucketer()) {
        self.scanner = scanner
        self.bucketer = bucketer
    }

    func fetch() async -> ProviderStatus {
        let events = scanner.scan()
        guard !events.isEmpty else {
            return ProviderStatus(id: id, session: nil, weekly: nil,
                                  source: .localEstimate, lastUpdated: Date(),
                                  errorMessage: "No local Claude Code activity found")
        }
        var b = bucketer
        b.calibration = b.calibrated(from: events)
        let session = b.sessionWindow(events: events)
        let weekly = b.weeklyWindow(events: events)
        return ProviderStatus(id: id, session: session, weekly: weekly,
                              source: .localEstimate, lastUpdated: Date(), errorMessage: nil)
    }
}
