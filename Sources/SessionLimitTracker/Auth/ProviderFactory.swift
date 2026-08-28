import Foundation

/// Builds the concrete provider for an id given its connection — the hybrid switch.
enum ProviderFactory {

    static func make(for id: ProviderID, connection: ProviderConnection, vault: CredentialVault) -> UsageProvider {
        switch connection.method {
        case .manual:
            return ManualProvider(id: id,
                                  session: connection.manualSession.map { UsageWindow(label: "Current session", percentUsed: $0, resetsAt: nil) },
                                  weekly: connection.manualWeekly.map { UsageWindow(label: "All models", percentUsed: $0, resetsAt: nil) })

        case .detectCodex:
            return CodexProvider()

        case .oauth, .detectClaudeCode, .apiKey, .sessionToken:
            // Claude: any stored bearer token (OAuth / detected / setup-token pasted
            // as api key or session token) feeds the usage endpoint.
            if id == .claude {
                return ClaudeOAuthProvider(vault: vault, method: connection.method)
            }
            if connection.method == .oauth {
                return ConnectionStatusProvider(id: id, note: "Signed in via OAuth — \(id.displayName) publishes no consumer usage endpoint; use Manual for numbers")
            }
            return ConnectionStatusProvider(id: id, note: "Connected; live usage for \(id.displayName) isn't published — use Manual for now")

        case .none:
            // Defaults per provider.
            switch id {
            case .claude:
                return ClaudeLocalProvider()
            case .openai:
                // Real ChatGPT limits from Codex's cached rate_limits, if signed in.
                return CodexProvider()
            case .gemini:
                return CLILocalProvider(id: id, root: geminiRoot, bucketer: WindowBucketer())
            }
        }
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    /// Best-effort default location for Gemini CLI session logs.
    private static var geminiRoot: URL { home.appendingPathComponent(".gemini/tmp") }
}
