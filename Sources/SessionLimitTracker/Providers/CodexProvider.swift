import Foundation

/// GPT/ChatGPT usage via Codex (OpenAI's CLI): reads the real rate limits Codex
/// caches from its ChatGPT-authenticated API responses. Real numbers, no request
/// cost — badged `.authoritative`.
struct CodexProvider: UsageProvider {
    let id: ProviderID = .openai

    func fetch() async -> ProviderStatus {
        guard let snap = CodexUsage.latest() else {
            let hint = CodexCLI.isInstalled()
                ? "No Codex usage yet — run a Codex session to populate limits."
                : "Codex CLI not found — sign in with `codex login`."
            return ProviderStatus(id: id, session: nil, weekly: nil, source: .unavailable,
                                  lastUpdated: Date(), errorMessage: hint)
        }
        return ProviderStatus(id: id, session: snap.session, weekly: snap.weekly,
                              source: .authoritative, lastUpdated: Date(), errorMessage: nil)
    }
}
