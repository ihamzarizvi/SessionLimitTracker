import Foundation

/// Codex (OpenAI "Sign in with ChatGPT") detection — entirely file-based, so it
/// works no matter how the app is launched (a GUI app has a minimal PATH and can't
/// reliably spawn the nvm-managed `codex` binary). Login state and usage both come
/// from files Codex writes: `~/.codex/auth.json` and `~/.codex/sessions/**`.
enum CodexCLI {

    static var authURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    private static let binaryCandidates: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex"]
    }()

    /// Codex present if it has written an auth file or a binary is in a known path.
    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: authURL.path)
            || binaryCandidates.contains { FileManager.default.isExecutableFile(atPath: $0) }
            || FileManager.default.fileExists(atPath: CodexUsage.sessionsRoot.path)
    }

    /// Logged in if `auth.json` carries a ChatGPT token (or an API key).
    static func isLoggedIn() -> Bool {
        guard let data = try? Data(contentsOf: authURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let mode = obj["auth_mode"] as? String, mode.lowercased().contains("chatgpt"),
           let tokens = obj["tokens"] as? [String: Any],
           let access = tokens["access_token"] as? String, !access.isEmpty {
            return true
        }
        if let key = obj["OPENAI_API_KEY"] as? String, !key.isEmpty { return true }
        return false
    }
}
