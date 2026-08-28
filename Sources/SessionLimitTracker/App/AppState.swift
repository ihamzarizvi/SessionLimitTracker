import SwiftUI
import Combine

/// Central observable state: current snapshot, settings, and poll orchestration.
@MainActor
final class AppState: ObservableObject {

    @Published private(set) var snapshot: UsageSnapshot
    @Published private(set) var isRefreshing = false

    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    @Published var colorblind: Bool {
        didSet { defaults.set(colorblind, forKey: Keys.colorblind) }
    }
    @Published var enabledProviders: Set<ProviderID> {
        didSet {
            defaults.set(enabledProviders.map(\.rawValue), forKey: Keys.enabled)
            objectWillChange.send()
            Task { await refresh() }   // reflect watchlist changes in the dock immediately
        }
    }

    // MARK: Alert & general settings

    @Published var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Keys.alertsEnabled) } }
    @Published var alertThresholds: [Int] { didSet { defaults.set(alertThresholds, forKey: Keys.thresholds) } }
    @Published var quietHoursEnabled: Bool { didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietEnabled) } }
    @Published var quietStartHour: Int { didSet { defaults.set(quietStartHour, forKey: Keys.quietStart) } }
    @Published var quietEndHour: Int { didSet { defaults.set(quietEndHour, forKey: Keys.quietEnd) } }
    @Published var menuBarShowPercent: Bool { didSet { defaults.set(menuBarShowPercent, forKey: Keys.menuBarPercent) } }
    @Published var launchAtLogin: Bool { didSet { LaunchAtLogin.setEnabled(launchAtLogin) } }

    // MARK: Notch rail settings
    @Published var railVisible: Bool { didSet { defaults.set(railVisible, forKey: Keys.railVisible) } }
    @Published var railAutoHide: Bool { didSet { defaults.set(railAutoHide, forKey: Keys.railAutoHide) } }
    @Published var railScale: Double { didSet { defaults.set(railScale, forKey: Keys.railScale) } }
    /// Which screen edge the rail docks to.
    @Published var railEdge: RailEdge { didSet { defaults.set(railEdge.rawValue, forKey: Keys.railEdge) } }
    /// Vertical position: distance (points) from the top of the screen to the top of the rail.
    @Published var railVerticalOffset: Double { didSet { defaults.set(railVerticalOffset, forKey: Keys.railVOffset) } }
    /// Bumped to force the rail panel to re-lay-out (e.g. after resetting position).
    @Published var railLayoutTick: Int = 0

    /// Store the dragged vertical offset without triggering a re-layout (the panel
    /// snaps itself). Keeps the @Published value in sync for the settings UI.
    func setRailVerticalOffset(_ points: Double) {
        defaults.set(points, forKey: Keys.railVOffset)
        railVerticalOffset = points
    }
    /// Reset the rail back near the top of its edge.
    func resetRailPosition() {
        railVerticalOffset = 12
        railLayoutTick &+= 1
    }

    /// Local-estimate poll cadence. The authoritative OAuth path enforces its own
    /// ≥180s floor separately (see plan); this drives the local providers.
    @Published var pollInterval: TimeInterval {
        didSet {
            defaults.set(pollInterval, forKey: Keys.pollInterval)
            if timer != nil { restartTimer() }
        }
    }

    let connections = ConnectionStore()
    private let alertEngine = AlertEngine()
    private let defaults: UserDefaults
    private var timer: Timer?

    private enum Keys {
        static let appearance = "appearanceMode"
        static let colorblind = "colorblindPalette"
        static let enabled = "enabledProviders"
        static let alertsEnabled = "alertsEnabled"
        static let thresholds = "alertThresholds"
        static let quietEnabled = "quietHoursEnabled"
        static let quietStart = "quietStartHour"
        static let quietEnd = "quietEndHour"
        static let menuBarPercent = "menuBarShowPercent"
        static let pollInterval = "pollInterval"
        static let railVisible = "railVisible"
        static let railAutoHide = "railAutoHide"
        static let railScale = "railScale"
        static let railEdge = "railEdge"
        static let railVOffset = "railVerticalOffset"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        self.colorblind = defaults.bool(forKey: Keys.colorblind)
        if let raw = defaults.array(forKey: Keys.enabled) as? [String] {
            self.enabledProviders = Set(raw.compactMap(ProviderID.init(rawValue:)))
        } else {
            self.enabledProviders = [.claude, .openai, .gemini]
        }
        self.alertsEnabled = (defaults.object(forKey: Keys.alertsEnabled) as? Bool) ?? true
        self.alertThresholds = (defaults.array(forKey: Keys.thresholds) as? [Int]) ?? [75, 90, 100]
        self.quietHoursEnabled = defaults.bool(forKey: Keys.quietEnabled)
        self.quietStartHour = (defaults.object(forKey: Keys.quietStart) as? Int) ?? 22
        self.quietEndHour = (defaults.object(forKey: Keys.quietEnd) as? Int) ?? 8
        self.menuBarShowPercent = (defaults.object(forKey: Keys.menuBarPercent) as? Bool) ?? true
        self.pollInterval = (defaults.object(forKey: Keys.pollInterval) as? Double) ?? 30
        self.railVisible = (defaults.object(forKey: Keys.railVisible) as? Bool) ?? true
        self.railAutoHide = defaults.bool(forKey: Keys.railAutoHide)
        self.railScale = (defaults.object(forKey: Keys.railScale) as? Double) ?? 1.0
        self.railEdge = RailEdge(rawValue: defaults.string(forKey: Keys.railEdge) ?? "") ?? .right
        self.railVerticalOffset = (defaults.object(forKey: Keys.railVOffset) as? Double) ?? 12
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.snapshot = UsageSnapshot(
            providers: ProviderID.allCases.map(ProviderStatus.empty),
            capturedAt: Date()
        )
    }

    // MARK: - Providers

    /// Picks the concrete provider for each enabled id based on its stored
    /// connection method (the hybrid switch: local estimate vs authoritative vs manual).
    private func makeProviders() -> [UsageProvider] {
        enabledProviders.sorted { $0.rawValue < $1.rawValue }.map { id in
            ProviderFactory.make(for: id, connection: connections.connection(for: id), vault: connections.vault)
        }
    }

    // MARK: - Polling

    func start() {
        alertEngine.requestAuthorizationIfNeeded()
        Task { await refresh() }
        restartTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(5, pollInterval), repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = makeProviders()
        var results: [ProviderStatus] = []
        await withTaskGroup(of: ProviderStatus.self) { group in
            for p in providers { group.addTask { await p.fetch() } }
            for await status in group { results.append(status) }
        }
        // Keep a stable ordering for the UI.
        let order = ProviderID.allCases
        results.sort { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        let snap = UsageSnapshot(providers: results, capturedAt: Date())
        snapshot = snap

        alertEngine.evaluate(snap, config: AlertEngine.Config(
            enabled: alertsEnabled,
            thresholds: alertThresholds,
            quietHoursEnabled: quietHoursEnabled,
            quietStartHour: quietStartHour,
            quietEndHour: quietEndHour
        ))
    }

    // MARK: - Convenience for the UI

    var visibleStatuses: [ProviderStatus] {
        snapshot.providers.filter { enabledProviders.contains($0.id) }
    }

    var claude: ProviderStatus? { snapshot.status(for: .claude) }
}
