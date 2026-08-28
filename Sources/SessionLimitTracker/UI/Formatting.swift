import Foundation

enum Formatting {

    /// "Resets in 51 min" / "Resets in 2h 5m" for near windows, else "Resets Thu 12:00 AM".
    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "Resetting…" }
        if delta < 6 * 3600 {
            let minutes = Int((delta / 60).rounded())
            if minutes < 60 { return "Resets in \(minutes) min" }
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "Resets in \(h)h" : "Resets in \(h)h \(m)m"
        }
        return "Resets \(absolute.string(from: date))"
    }

    /// Compact reset label that fits under a rail ring: "51m", "2h", "Thu".
    static func resetShort(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "" }
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "now" }
        if delta < 3600 { return "\(Int((delta / 60).rounded()))m" }
        if delta < 6 * 3600 { return "\(Int((delta / 3600).rounded()))h" }
        return weekdayShort.string(from: date)
    }

    private static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// e.g. "Thu 12:00 AM"
    private static let absolute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f
    }()
}
