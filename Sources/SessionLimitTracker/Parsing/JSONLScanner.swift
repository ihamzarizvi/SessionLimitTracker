import Foundation

/// One token-usage event extracted from a Claude Code transcript line.
struct UsageEvent: Sendable {
    var timestamp: Date
    var tokens: Int
    var id: String          // dedup key (requestId / message.id / uuid)
    var isRateLimit: Bool    // true if this line records a rate-limit / limit-reached event
}

/// Scans `~/.claude/projects/**/*.jsonl` and extracts usage events.
///
/// Milestone-2 implementation: reads files modified within the look-back window,
/// parses each line defensively (the transcript schema varies across versions),
/// and dedups by id. Incremental byte-cursor tailing is a later optimization
/// (see plan) — a full parse of recent files is fast enough for a menu-bar poll.
struct JSONLScanner {

    var root: URL
    var lookback: TimeInterval

    init(root: URL? = nil, lookback: TimeInterval = 8 * 24 * 3600) {
        self.root = root ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        self.lookback = lookback
    }

    /// Returns deduped usage events with timestamps within `lookback` of now.
    func scan(now: Date = Date()) -> [UsageEvent] {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                     options: [.skipsHiddenFiles]) else { return [] }

        let cutoff = now.addingTimeInterval(-lookback)
        var seen = Set<String>()
        var events: [UsageEvent] = []

        for case let url as URL in en where url.pathExtension == "jsonl" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let mod = values?.contentModificationDate, mod < cutoff { continue }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let ev = Self.parseLine(String(line)) else { continue }
                guard ev.timestamp >= cutoff else { continue }
                if !ev.id.isEmpty {
                    if seen.contains(ev.id) { continue }
                    seen.insert(ev.id)
                }
                events.append(ev)
            }
        }
        return events.sorted { $0.timestamp < $1.timestamp }
    }

    /// Parse a single transcript line into a UsageEvent, or nil if it carries no usage.
    static func parseLine(_ line: String) -> UsageEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let ts = timestamp(in: obj) ?? Date()
        let rateLimited = isRateLimitEvent(obj)

        // Token usage lives under message.usage for assistant messages.
        let message = obj["message"] as? [String: Any]
        let usage = (message?["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any])

        guard let usage else {
            // A rate-limit marker with no token payload is still worth recording.
            return rateLimited ? UsageEvent(timestamp: ts, tokens: 0, id: dedupID(obj, message), isRateLimit: true) : nil
        }

        let tokens = intVal(usage["input_tokens"])
            + intVal(usage["output_tokens"])
            + intVal(usage["cache_creation_input_tokens"])
            + intVal(usage["cache_read_input_tokens"])

        return UsageEvent(timestamp: ts, tokens: tokens, id: dedupID(obj, message), isRateLimit: rateLimited)
    }

    // MARK: - Helpers

    private static func intVal(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }

    private static func dedupID(_ obj: [String: Any], _ message: [String: Any]?) -> String {
        if let r = obj["requestId"] as? String { return r }
        if let r = obj["request_id"] as? String { return r }
        if let m = message?["id"] as? String { return m }
        if let u = obj["uuid"] as? String { return u }
        return ""
    }

    // ISO8601DateFormatter is thread-safe for reading; only ever read here.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func timestamp(in obj: [String: Any]) -> Date? {
        guard let s = obj["timestamp"] as? String else {
            if let epoch = obj["timestamp"] as? Double { return Date(timeIntervalSince1970: epoch) }
            return nil
        }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    private static func isRateLimitEvent(_ obj: [String: Any]) -> Bool {
        // Look for common shapes: an error object with a rate_limit type, or a
        // stop_reason / string field mentioning the limit.
        if let err = obj["error"] as? [String: Any],
           let type = err["type"] as? String,
           type.contains("rate_limit") { return true }
        if let reason = obj["stop_reason"] as? String, reason.contains("limit") { return true }
        return false
    }
}
