import Foundation

/// Anything that can report usage for one provider. Concrete providers:
/// ClaudeLocalProvider, ClaudeOAuthProvider, CodexProvider, GeminiProvider, ManualProvider.
protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// Fetch the latest status. Implementations must not throw — they return a
    /// ProviderStatus carrying an errorMessage instead, so one failing provider
    /// never breaks the whole snapshot.
    func fetch() async -> ProviderStatus
}
