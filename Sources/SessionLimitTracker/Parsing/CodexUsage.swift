import Foundation

/// Reads the real ChatGPT rate limits that the Codex CLI caches in its session
/// rollout files (`~/.codex/sessions/**/*.jsonl`). These are the actual numbers
/// from Codex's ChatGPT-authenticated API responses — no request/quota cost.
///
/// Shape: `"rate_limits": { "primary": {used_percent, window_minutes:300, resets_at},
/// "secondary": {…, window_minutes:10080}, "plan_type": "plus" }`.
enum CodexUsage {

    struct Snapshot { var session: UsageWindow?; var weekly: UsageWindow?; var plan: String? }

    static var sessionsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    /// Most recent rate-limit snapshot, or nil if none found.
    static func latest(lookback: TimeInterval = 14 * 24 * 3600, now: Date = Date()) -> Snapshot? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: sessionsRoot,
                                     includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        let cutoff = now.addingTimeInterval(-lookback)
        var files: [(URL, Date)] = []
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if mod >= cutoff { files.append((url, mod)) }
        }
        // Newest file first; return the last rate_limits found in the newest file that has one.
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var last: [String: Any]?
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.contains("rate_limits") {
                if let rl = findRateLimits(in: String(line)) { last = rl }
            }
            if let rl = last { return snapshot(from: rl) }
        }
        return nil
    }

    // MARK: - Parsing

    private static func findRateLimits(in line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return search(obj)
    }

    private static func search(_ any: Any) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if let rl = dict["rate_limits"] as? [String: Any] { return rl }
            for v in dict.values { if let r = search(v) { return r } }
        } else if let arr = any as? [Any] {
            for v in arr { if let r = search(v) { return r } }
        }
        return nil
    }

    private static func snapshot(from rl: [String: Any]) -> Snapshot {
        Snapshot(
            session: window(rl["primary"] as? [String: Any], label: "Current session"),
            weekly: window(rl["secondary"] as? [String: Any], label: "All models"),
            plan: rl["plan_type"] as? String
        )
    }

    private static func window(_ obj: [String: Any]?, label: String) -> UsageWindow? {
        guard let obj, let used = number(obj["used_percent"]) else { return nil }
        let reset = number(obj["resets_at"]).map { Date(timeIntervalSince1970: $0) }
        return UsageWindow(label: label, percentUsed: used / 100, resetsAt: reset)
    }

    private static func number(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
