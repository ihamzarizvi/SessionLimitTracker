import Foundation
import UserNotifications

/// Fires native notifications when a usage window crosses a configured threshold,
/// de-duped so each threshold fires at most once per window instance (keyed by
/// the window's reset time). Safe to use without a bundle (it no-ops).
@MainActor
final class AlertEngine {

    struct Config {
        var enabled: Bool
        var thresholds: [Int]          // percent values, e.g. [75, 90, 100]
        var quietHoursEnabled: Bool
        var quietStartHour: Int         // 0...23
        var quietEndHour: Int           // 0...23
    }

    /// Highest threshold already fired, keyed by "provider|label|resetEpoch".
    private var firedFor: [String: Int] = [:]
    private var authorized = false
    private let hasBundle = Bundle.main.bundleIdentifier != nil

    func requestAuthorizationIfNeeded() {
        guard hasBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    func evaluate(_ snapshot: UsageSnapshot, config: Config, now: Date = Date()) {
        guard config.enabled, !inQuietHours(config: config, now: now) else { return }
        for status in snapshot.providers {
            evaluateWindow(status.session, provider: status.name, config: config)
            evaluateWindow(status.weekly, provider: status.name, config: config)
        }
    }

    private func evaluateWindow(_ window: UsageWindow?, provider: String, config: Config) {
        guard let window else { return }
        let key = "\(provider)|\(window.label)|\(Int(window.resetsAt?.timeIntervalSince1970 ?? 0))"
        let pct = Int((window.percentUsed * 100).rounded(.down))
        let already = firedFor[key] ?? -1
        // Fire the highest crossed threshold not yet notified for this window instance.
        let crossed = config.thresholds.filter { pct >= $0 && $0 > already }.max()
        guard let level = crossed else { return }
        firedFor[key] = level
        fire(title: "\(provider) \(window.label)",
             body: level >= 100 ? "Limit reached (\(pct)% used)." : "\(level)% of your limit used.")
    }

    private func fire(title: String, body: String) {
        guard hasBundle, authorized else {
            NSLog("[alert] \(title): \(body)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func inQuietHours(config: Config, now: Date) -> Bool {
        guard config.quietHoursEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        let s = config.quietStartHour, e = config.quietEndHour
        if s == e { return false }
        return s < e ? (hour >= s && hour < e) : (hour >= s || hour < e) // handle overnight ranges
    }
}
