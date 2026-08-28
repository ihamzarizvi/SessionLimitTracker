import Foundation
import Security

/// Reads the OAuth access token that Claude Code stores on login. Used only when
/// the user explicitly enables the "Detect Claude Code login" method. We never
/// copy or persist the token — it is read live, per request.
///
/// Claude Code stores the token either in `~/.claude/.credentials.json` or, more
/// commonly on macOS, in the Keychain under service "Claude Code-credentials".
enum ClaudeCredentials {

    static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private static let keychainService = "Claude Code-credentials"

    // In-memory cache so we touch the Keychain at most once per app session — this
    // is what stops the repeated password/Keychain prompts on every poll. Cleared
    // by `invalidate()` when a token is actually rejected (401/403).
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedToken: String?
    nonisolated(unsafe) private static var didResolve = false

    /// Best-effort extraction of the current access token, or nil if not present.
    /// Cached for the session; tries the file, then our own Keychain read, then the
    /// `security` tool (which can read the CLI's item — the source of the one-time
    /// prompt, since the item's ACL is bound to the `claude` binary).
    static func tokenFromClaudeCode() -> String? {
        lock.lock()
        if didResolve { let t = cachedToken; lock.unlock(); return t }
        lock.unlock()

        let token = resolveUncached()

        lock.lock()
        cachedToken = token
        didResolve = true
        lock.unlock()
        return token
    }

    /// Drop the cached token so the next read re-fetches (call when a token is rejected).
    static func invalidate() {
        lock.lock(); cachedToken = nil; didResolve = false; lock.unlock()
    }

    private static func resolveUncached() -> String? {
        if let data = try? Data(contentsOf: credentialsURL), let token = parseToken(data) {
            return token
        }
        if let data = readKeychainBlob(), let token = parseToken(data) {
            return token
        }
        if let data = readKeychainViaSecurityCLI(), let token = parseToken(data) {
            return token
        }
        return nil
    }

    /// Whether a Claude Code login appears present, cheaply (no Keychain prompt):
    /// the CLI being installed, or the credentials file existing.
    static func looksConnected() -> Bool {
        ClaudeCLI.isInstalled() || FileManager.default.fileExists(atPath: credentialsURL.path)
    }

    // MARK: - Parsing

    private static func parseToken(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let oauth = obj["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String, !token.isEmpty { return token }
        if let token = obj["accessToken"] as? String, !token.isEmpty { return token }
        if let token = obj["access_token"] as? String, !token.isEmpty { return token }
        return nil
    }

    /// Reads the raw JSON blob from the CLI's Keychain item. The first access from
    /// this (different) app may raise a one-time Keychain permission prompt.
    private static func readKeychainBlob() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }

    /// Fallback that shells out to `/usr/bin/security`, which can read the CLI's
    /// Keychain item (the user approves a one-time prompt). Blocks briefly.
    private static func readKeychainViaSecurityCLI() -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        // Output is the blob followed by a trailing newline.
        return data.isEmpty ? nil : data
    }
}
