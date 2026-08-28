import Foundation

/// Result of `claude auth status`.
struct ClaudeAuthStatus: Sendable {
    var loggedIn: Bool
    var email: String?
    var subscriptionType: String?
    var authMethod: String?
}

/// Thin wrapper over the official `claude` CLI. We use it for compliant auth
/// verification (`claude auth status`) — the CLI is authorized to read this, so
/// it's the cleanest way to confirm a Claude connection without touching the
/// undocumented usage endpoint just to test. (The CLI has no usage subcommand;
/// `/usage` is interactive-only, so real numbers still come from the endpoint.)
enum ClaudeCLI {

    /// Common install locations, newest CLI first.
    private static let candidates: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.claude/local/claude"
        ]
    }()

    static func binaryPath() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func isInstalled() -> Bool { binaryPath() != nil }

    /// Runs `claude auth status` and parses the JSON. Returns nil if the CLI is
    /// missing or the call fails. Blocks briefly — call off the main thread.
    static func authStatus() -> ClaudeAuthStatus? {
        guard let output = run(["auth", "status"]),
              let data = extractJSON(output),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ClaudeAuthStatus(
            loggedIn: (obj["loggedIn"] as? Bool) ?? false,
            email: obj["email"] as? String,
            subscriptionType: obj["subscriptionType"] as? String,
            authMethod: obj["authMethod"] as? String
        )
    }

    // MARK: - Process helpers

    private static func run(_ args: [String], timeout: TimeInterval = 12) -> String? {
        guard let path = binaryPath() else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }

        // Guard against a hung CLI.
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline { usleep(50_000) }
        if proc.isRunning { proc.terminate(); return nil }

        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    /// The CLI may print a line or two before the JSON object; grab from the first `{`.
    private static func extractJSON(_ s: String) -> Data? {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return nil }
        return String(s[start...end]).data(using: .utf8)
    }
}
