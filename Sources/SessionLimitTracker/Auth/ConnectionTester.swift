import Foundation

struct ConnectionTestResult: Sendable {
    var ok: Bool
    var message: String
}

/// Verifies a saved connection actually works — the "connection test" the wizard
/// runs after login. Where a provider exposes a cheap authenticated endpoint we
/// hit it for real; otherwise we confirm the credential is present and say so.
enum ConnectionTester {

    static func test(id: ProviderID, connection: ProviderConnection, vault: CredentialVault) async -> ConnectionTestResult {
        switch (id, connection.method) {
        case (_, .manual):
            return .init(ok: true, message: "Manual values saved.")

        case (.claude, .detectClaudeCode):
            // Official CLI auth check — compliant, no Keychain prompt, reports account + plan.
            if let s = await Task.detached(operation: { ClaudeCLI.authStatus() }).value {
                guard s.loggedIn else {
                    return .init(ok: false, message: "Claude Code is installed but not logged in — run `claude auth login`.")
                }
                let plan = s.subscriptionType.map { " · \($0)" } ?? ""
                return .init(ok: true, message: "Signed in as \(s.email ?? "your account")\(plan) (via Claude Code).")
            }
            return await testClaudeBearer(ClaudeCredentials.tokenFromClaudeCode())

        case (.claude, .oauth), (.claude, .apiKey), (.claude, .sessionToken):
            // A pasted setup-token / OAuth token in our own vault — test it directly.
            return await testClaudeBearer(vault.read(for: .claude, method: connection.method))

        case (.openai, .detectCodex):
            let loggedIn = await Task.detached(operation: { CodexCLI.isLoggedIn() }).value
            guard loggedIn || CodexCLI.isInstalled() else {
                return .init(ok: false, message: "Codex CLI not found or not logged in — run `codex login`.")
            }
            if let snap = CodexUsage.latest() {
                let plan = snap.plan.map { " · \($0)" } ?? ""
                let pct = snap.session?.percentText ?? snap.weekly?.percentText ?? "ok"
                return .init(ok: true, message: "Reading ChatGPT limits from Codex\(plan) (\(pct) session).")
            }
            return .init(ok: true, message: "Signed in with ChatGPT via Codex. Run a Codex session so limits populate.")

        case (.openai, .apiKey):
            return await testBearer(url: "https://api.openai.com/v1/models",
                                    token: vault.read(for: id, method: .apiKey))

        case (.gemini, .apiKey):
            guard let key = vault.read(for: id, method: .apiKey) else {
                return .init(ok: false, message: "No API key stored.")
            }
            return await testStatus(url: "https://generativelanguage.googleapis.com/v1beta/models?key=\(key)")

        case (_, .apiKey), (_, .sessionToken), (_, .oauth):
            let present = vault.hasCredential(for: id, method: connection.method)
            return .init(ok: present,
                         message: present ? "Credential stored. No automated test endpoint for \(id.displayName)."
                                          : "No credential stored.")

        default:
            return .init(ok: false, message: "Not connected.")
        }
    }

    /// Verifies a Claude bearer token against the usage endpoint.
    private static func testClaudeBearer(_ token: String?) async -> ConnectionTestResult {
        guard let token else { return .init(ok: false, message: "No Claude token available.") }
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            return .init(ok: false, message: "Bad URL.")
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("SessionLimitTracker/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200..<300:
                if let p = ClaudeOAuthProvider.parse(data), let s = p.session {
                    return .init(ok: true, message: "Authenticated — usage reachable (\(s.percentText) session).")
                }
                return .init(ok: true, message: "Authenticated — usage reachable.")
            case 401, 403: return .init(ok: false, message: "Token rejected (HTTP \(code)).")
            case 429:      return .init(ok: true, message: "Authenticated (rate-limited — numbers will fill in).")
            default:       return .init(ok: false, message: "Unexpected response (HTTP \(code)).")
            }
        } catch {
            return .init(ok: false, message: error.localizedDescription)
        }
    }

    private static func testBearer(url: String, token: String?) async -> ConnectionTestResult {
        guard let token, let u = URL(string: url) else { return .init(ok: false, message: "No API key stored.") }
        var req = URLRequest(url: u)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        return await run(req)
    }

    private static func testStatus(url: String) async -> ConnectionTestResult {
        guard let u = URL(string: url) else { return .init(ok: false, message: "Bad test URL.") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        return await run(req)
    }

    private static func run(_ req: URLRequest) async -> ConnectionTestResult {
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch code {
            case 200..<300: return .init(ok: true, message: "Authenticated — endpoint reachable.")
            case 401, 403:  return .init(ok: false, message: "Credential rejected (HTTP \(code)).")
            case 429:       return .init(ok: true, message: "Authenticated (rate-limited).")
            default:        return .init(ok: false, message: "Unexpected response (HTTP \(code)).")
            }
        } catch {
            return .init(ok: false, message: error.localizedDescription)
        }
    }
}
