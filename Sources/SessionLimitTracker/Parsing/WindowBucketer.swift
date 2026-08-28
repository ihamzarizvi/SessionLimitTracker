import Foundation

/// Token capacities used to turn raw token sums into a percentage. These are
/// rough defaults. `sessionTokenCapacity` gets refined when a rate-limit event
/// reveals the true 5-hour capacity (tokens-in-window at limit == capacity).
/// `weeklyTokenCapacity` stays at its default until a weekly-limit event is seen
/// (we can't reliably tell a weekly limit from a session limit in the logs).
struct Calibration: Codable, Sendable {
    var sessionTokenCapacity: Double
    var weeklyTokenCapacity: Double

    static let `default` = Calibration(
        sessionTokenCapacity: 19_000_000,   // placeholder — calibrated at first rate-limit
        weeklyTokenCapacity: 300_000_000     // placeholder — calibrated at first weekly limit
    )
}

/// Aggregates usage events into the two windows Claude enforces:
/// a 5-hour rolling session window and a weekly all-models window.
struct WindowBucketer {

    var sessionLength: TimeInterval = 5 * 3600
    /// Weekday the weekly window resets on (1 = Sunday ... 5 = Thursday). Configurable.
    var weeklyResetWeekday: Int = 5
    var calibration: Calibration = .default
    var calendar: Calendar = .current

    // MARK: - Session (5h rolling)

    func sessionWindow(events: [UsageEvent], now: Date = Date()) -> UsageWindow {
        // Determine the active session block: blocks start at the first event and
        // last `sessionLength`; a new block starts once that elapses.
        var blockStart: Date?
        var blockTokens = 0
        var lastStart: Date?
        var lastTokens = 0

        for ev in events { // events are pre-sorted ascending
            if let start = blockStart, ev.timestamp < start.addingTimeInterval(sessionLength) {
                blockTokens += ev.tokens
            } else {
                lastStart = blockStart
                lastTokens = blockTokens
                blockStart = ev.timestamp
                blockTokens = ev.tokens
            }
        }
        // Flush the final block as the most recent one.
        if let start = blockStart {
            lastStart = start
            lastTokens = blockTokens
        }

        guard let start = lastStart else {
            return UsageWindow(label: "Current session", percentUsed: 0, resetsAt: nil)
        }
        let resetsAt = start.addingTimeInterval(sessionLength)
        // If the window already elapsed, there is no active session.
        if now >= resetsAt {
            return UsageWindow(label: "Current session", percentUsed: 0, resetsAt: nil)
        }
        let pct = Double(lastTokens) / max(1, calibration.sessionTokenCapacity)
        return UsageWindow(label: "Current session", percentUsed: pct, resetsAt: resetsAt)
    }

    // MARK: - Weekly

    func weeklyWindow(events: [UsageEvent], now: Date = Date()) -> UsageWindow {
        let start = mostRecentReset(before: now)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 24 * 3600)
        let tokens = events.filter { $0.timestamp >= start }.reduce(0) { $0 + $1.tokens }
        let pct = Double(tokens) / max(1, calibration.weeklyTokenCapacity)
        return UsageWindow(label: "All models", percentUsed: pct, resetsAt: end)
    }

    /// Most recent occurrence of the reset weekday at 00:00 local, at or before `date`.
    private func mostRecentReset(before date: Date) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let delta = (weekday - weeklyResetWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: startOfDay) ?? startOfDay
    }

    // MARK: - Calibration from rate-limit events

    /// If a rate-limit event exists, the tokens accumulated in the 5-hour block
    /// containing it equal the real session capacity. Only `sessionTokenCapacity`
    /// is refined (see `Calibration` note). Returns an updated Calibration, or the
    /// current one unchanged.
    func calibrated(from events: [UsageEvent], now: Date = Date()) -> Calibration {
        guard let limit = events.last(where: { $0.isRateLimit }) else { return calibration }
        var cal = calibration
        let blockStart = limit.timestamp.addingTimeInterval(-sessionLength)
        let sessionTokens = events.filter { $0.timestamp >= blockStart && $0.timestamp <= limit.timestamp }
            .reduce(0) { $0 + $1.tokens }
        if sessionTokens > 0 { cal.sessionTokenCapacity = Double(sessionTokens) }
        return cal
    }
}
