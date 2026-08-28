import Foundation
import Combine

/// How a provider is connected. Drives which concrete provider the factory builds.
enum ConnectionMethod: String, Codable, CaseIterable, Sendable {
    case none               // not connected → local estimate (Claude) or unavailable
    case detectClaudeCode   // reuse ~/.claude OAuth token
    case detectCodex        // reuse Codex (ChatGPT) login → cached rate limits
    case oauth              // our own OAuth sign-in
    case apiKey             // provider API key
    case sessionToken       // pasted browser session token
    case manual             // user-entered cap

    var label: String {
        switch self {
        case .none: return "Not connected"
        case .detectClaudeCode: return "Detect Claude Code login"
        case .detectCodex: return "Detect Codex (Sign in with ChatGPT)"
        case .oauth: return "Sign in (OAuth)"
        case .apiKey: return "API key"
        case .sessionToken: return "Paste session token"
        case .manual: return "Manual"
        }
    }

    /// Whether this method reflects paid-subscription usage (policy-sensitive).
    var isSubscriptionAuth: Bool {
        self == .detectClaudeCode || self == .oauth || self == .sessionToken
    }
}

enum ConnectionState: Equatable, Sendable {
    case notConnected
    case connected
    case needsAuth
    case error(String)

    var label: String {
        switch self {
        case .notConnected: return "Not connected"
        case .connected: return "Connected"
        case .needsAuth: return "Needs sign-in"
        case .error(let m): return m
        }
    }
    var symbol: String {
        switch self {
        case .notConnected: return "circle"
        case .connected: return "checkmark.circle.fill"
        case .needsAuth: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
}

struct ProviderConnection: Sendable {
    var provider: ProviderID
    var method: ConnectionMethod
    var state: ConnectionState
    var manualSession: Double?   // 0...1
    var manualWeekly: Double?    // 0...1
}

/// Persists per-provider connection method + manual values, and exposes the vault.
/// Method choice lives in UserDefaults; secrets live only in the Keychain.
@MainActor
final class ConnectionStore: ObservableObject {

    let vault = CredentialVault()
    private let defaults: UserDefaults
    @Published private var methods: [ProviderID: ConnectionMethod] = [:]
    @Published private var manualSession: [ProviderID: Double] = [:]
    @Published private var manualWeekly: [ProviderID: Double] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.dictionary(forKey: "connectionMethods") as? [String: String] {
            for (k, v) in raw {
                if let id = ProviderID(rawValue: k), let m = ConnectionMethod(rawValue: v) { methods[id] = m }
            }
        }
        manualSession = decodeDoubles("manualSession")
        manualWeekly = decodeDoubles("manualWeekly")
    }

    private func decodeDoubles(_ key: String) -> [ProviderID: Double] {
        var out: [ProviderID: Double] = [:]
        if let raw = defaults.dictionary(forKey: key) as? [String: Double] {
            for (k, v) in raw { if let id = ProviderID(rawValue: k) { out[id] = v } }
        }
        return out
    }

    private func persistMethods() {
        defaults.set(Dictionary(uniqueKeysWithValues: methods.map { ($0.key.rawValue, $0.value.rawValue) }),
                     forKey: "connectionMethods")
    }
    private func persistManual() {
        defaults.set(Dictionary(uniqueKeysWithValues: manualSession.map { ($0.key.rawValue, $0.value) }), forKey: "manualSession")
        defaults.set(Dictionary(uniqueKeysWithValues: manualWeekly.map { ($0.key.rawValue, $0.value) }), forKey: "manualWeekly")
    }

    func method(for id: ProviderID) -> ConnectionMethod { methods[id] ?? .none }

    // MARK: OAuth client config (non-secret; token itself lives in the vault)

    func oauthConfig(for id: ProviderID) -> OAuthConfig {
        if let data = defaults.data(forKey: "oauthConfig.\(id.rawValue)"),
           let cfg = try? JSONDecoder().decode(OAuthConfig.self, from: data) {
            return cfg
        }
        return OAuthConfig.defaults(for: id)
    }

    func setOAuthConfig(_ config: OAuthConfig, for id: ProviderID) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: "oauthConfig.\(id.rawValue)")
        }
    }

    func setMethod(_ method: ConnectionMethod, for id: ProviderID) {
        methods[id] = method
        persistMethods()
    }

    func setManual(session: Double?, weekly: Double?, for id: ProviderID) {
        manualSession[id] = session
        manualWeekly[id] = weekly
        persistManual()
    }

    func disconnect(_ id: ProviderID) {
        let m = method(for: id)
        vault.delete(for: id, method: m)
        methods[id] = ConnectionMethod.none
        manualSession[id] = nil
        manualWeekly[id] = nil
        persistMethods(); persistManual()
    }

    /// Compute the live connection state for the UI.
    func connection(for id: ProviderID) -> ProviderConnection {
        let m = method(for: id)
        let state: ConnectionState
        switch m {
        case ConnectionMethod.none:
            state = .notConnected
        case .manual:
            state = (manualSession[id] != nil || manualWeekly[id] != nil) ? .connected : .needsAuth
        case .detectClaudeCode:
            // Cheap check (CLI installed / creds file present) to avoid a Keychain
            // prompt on every render; the wizard's connection test does the real verify.
            state = ClaudeCredentials.looksConnected() ? .connected : .needsAuth
        case .detectCodex:
            let authFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
            state = (CodexCLI.isInstalled() || FileManager.default.fileExists(atPath: authFile.path)) ? .connected : .needsAuth
        case .oauth, .apiKey, .sessionToken:
            state = vault.hasCredential(for: id, method: m) ? .connected : .needsAuth
        }
        return ProviderConnection(provider: id, method: m, state: state,
                                  manualSession: manualSession[id], manualWeekly: manualWeekly[id])
    }
}
