import Foundation

/// Caches the authoritative result and enforces the endpoint's ≥180s poll floor
/// across provider instances (a fresh provider is built each refresh).
actor OAuthUsageCache {
    static let shared = OAuthUsageCache()
    private var lastReal: (Date, ProviderStatus)?
    private var lastAttempt: Date?

    func realIfFresh(floor: TimeInterval, now: Date) -> ProviderStatus? {
        guard let (t, s) = lastReal, now.timeIntervalSince(t) < floor else { return nil }
        return s
    }
    func canAttempt(floor: TimeInterval, now: Date) -> Bool {
        guard let a = lastAttempt else { return true }
        return now.timeIntervalSince(a) >= floor
    }
    func noteAttempt(_ now: Date) { lastAttempt = now }
    func setReal(_ s: ProviderStatus, now: Date) { lastReal = (now, s) }
}

/// Authoritative Claude provider (OPT-IN). Polls the same endpoint `/usage` uses
/// for real, shared-pool numbers, then falls back to the local estimate whenever
/// the endpoint path can't produce numbers — so the UI is never left blank.
struct ClaudeOAuthProvider: UsageProvider {
    let id: ProviderID = .claude
    var vault: CredentialVault
    var method: ConnectionMethod   // .oauth or .detectClaudeCode

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let pollFloor: TimeInterval = 180

    func fetch() async -> ProviderStatus {
        let now = Date()
        if let real = await OAuthUsageCache.shared.realIfFresh(floor: Self.pollFloor, now: now) {
            return real
        }
        // Respect the poll floor even on failure: between attempts, show the estimate.
        guard await OAuthUsageCache.shared.canAttempt(floor: Self.pollFloor, now: now) else {
            return await localFallback(note: "Live poll throttled (≤ every 3 min) — showing local estimate.")
        }
        await OAuthUsageCache.shared.noteAttempt(now)

        guard let token = resolveToken() else {
            return await localFallback(note: "Couldn't read your Claude sign-in token — showing local estimate.")
        }

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("SessionLimitTracker/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 {
                return await localFallback(note: "Usage endpoint rate-limited (429) — showing local estimate.")
            }
            guard (200..<300).contains(code) else {
                if code == 401 || code == 403 {
                    // Token rejected — drop the cache so it's re-read next time.
                    if method == .detectClaudeCode { ClaudeCredentials.invalidate() }
                }
                return await localFallback(note: "Usage endpoint returned HTTP \(code) — showing local estimate.")
            }
            guard let parsed = Self.parse(data) else {
                return await localFallback(note: "Couldn't read the usage response — showing local estimate.")
            }
            let result = ProviderStatus(id: id, session: parsed.session, weekly: parsed.weekly,
                                        source: .authoritative, lastUpdated: now, errorMessage: nil)
            await OAuthUsageCache.shared.setReal(result, now: now)
            return result
        } catch {
            return await localFallback(note: "Usage request failed (\(error.localizedDescription)) — showing local estimate.")
        }
    }

    private func resolveToken() -> String? {
        switch method {
        case .detectClaudeCode:
            return ClaudeCredentials.tokenFromClaudeCode()
        case .oauth, .apiKey, .sessionToken:
            // A pasted `claude setup-token` (stored under whichever method) or an
            // OAuth token — no cross-app Keychain prompt, it's in our own vault.
            return vault.read(for: id, method: method) ?? ClaudeCredentials.tokenFromClaudeCode()
        default:
            return ClaudeCredentials.tokenFromClaudeCode()
        }
    }

    /// Local estimate with a note so the user knows why it's not the authoritative number.
    private func localFallback(note: String) async -> ProviderStatus {
        var status = await ClaudeLocalProvider().fetch()
        status.errorMessage = (status.session == nil && status.weekly == nil)
            ? (status.errorMessage ?? note)
            : note
        return status
    }

    // MARK: - Response parsing (real /api/oauth/usage shape)

    struct Parsed { var session: UsageWindow?; var weekly: UsageWindow? }

    /// Real shape: `{ "five_hour": {"utilization": 19.0, "resets_at": "…"},
    /// "seven_day": {…}, "limits": [ {group,kind,percent,resets_at}, … ] }`.
    /// utilization/percent are 0–100. Falls back to a tolerant scan for other shapes.
    static func parse(_ data: Data) -> Parsed? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        var session = window(from: root["five_hour"] as? [String: Any], label: "Current session")
        var weekly = window(from: root["seven_day"] as? [String: Any], label: "All models")

        if session == nil || weekly == nil, let limits = root["limits"] as? [[String: Any]] {
            for l in limits {
                let group = l["group"] as? String
                let kind = l["kind"] as? String
                guard let pct = numeric(l["percent"]) else { continue }
                let reset = (l["resets_at"] as? String).flatMap(parseDate)
                if group == "session", session == nil {
                    session = UsageWindow(label: "Current session", percentUsed: normalize(pct), resetsAt: reset)
                }
                if group == "weekly", kind == "weekly_all", weekly == nil {
                    weekly = UsageWindow(label: "All models", percentUsed: normalize(pct), resetsAt: reset)
                }
            }
        }

        if session == nil && weekly == nil { return tolerant(root) }
        return Parsed(session: session, weekly: weekly)
    }

    private static func window(from obj: [String: Any]?, label: String) -> UsageWindow? {
        guard let obj, let u = numeric(obj["utilization"]) ?? numeric(obj["percent"]) else { return nil }
        let reset = (obj["resets_at"] as? String).flatMap(parseDate)
        return UsageWindow(label: label, percentUsed: normalize(u), resetsAt: reset)
    }

    /// Utilization is on a 0–100 scale; normalize to 0–1.
    private static func normalize(_ v: Double) -> Double { v > 1 ? v / 100 : v }

    private static func numeric(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    /// Robust ISO-8601 parse that tolerates fractional seconds (incl. microseconds) + offset.
    static func parseDate(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter(); withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Truncate any sub-second fraction to 3 digits, then retry.
        if let range = s.range(of: #"\.\d+"#, options: .regularExpression) {
            var trimmed = s
            let frac = String(s[range]).prefix(4) // ".NNN"
            trimmed.replaceSubrange(range, with: frac)
            if let d = withFrac.date(from: trimmed) { return d }
        }
        return nil
    }

    // MARK: - Tolerant fallback for unknown shapes

    private static func tolerant(_ root: [String: Any]) -> Parsed? {
        var candidates: [(String, [String: Any])] = []
        func collect(_ dict: [String: Any]) {
            for (k, v) in dict where v is [String: Any] {
                let child = v as! [String: Any]
                candidates.append((k.lowercased(), child)); collect(child)
            }
        }
        collect(root)
        func match(_ keys: [String], _ label: String) -> UsageWindow? {
            guard let (_, obj) = candidates.first(where: { name, obj in
                keys.contains(where: { name.contains($0) }) && (numeric(obj["utilization"]) ?? numeric(obj["percent"])) != nil
            }) else { return nil }
            let u = numeric(obj["utilization"]) ?? numeric(obj["percent"]) ?? 0
            return UsageWindow(label: label, percentUsed: normalize(u), resetsAt: (obj["resets_at"] as? String).flatMap(parseDate))
        }
        let s = match(["5", "five", "hour", "session"], "Current session")
        let w = match(["7", "seven", "day", "week"], "All models")
        if s == nil && w == nil { return nil }
        return Parsed(session: s, weekly: w)
    }
}
