import Foundation
import AuthenticationServices
import AppKit
import CryptoKit

/// Per-provider OAuth client configuration. Endpoints + scopes are prefilled with
/// sensible defaults; the user supplies their own `clientID` (registering an OAuth
/// app is the legitimate way — we never ship spoofed client credentials).
struct OAuthConfig: Codable, Sendable, Equatable {
    var clientID: String
    var authorizeURL: String
    var tokenURL: String
    var scopes: String
    var redirectURI: String
    var callbackScheme: String

    static func defaults(for id: ProviderID) -> OAuthConfig {
        switch id {
        case .claude:
            return OAuthConfig(
                clientID: "",
                authorizeURL: "https://claude.ai/oauth/authorize",
                tokenURL: "https://console.anthropic.com/v1/oauth/token",
                scopes: "org:read_usage",
                redirectURI: "com.sessionlimittracker://oauth",
                callbackScheme: "com.sessionlimittracker")
        case .openai:
            return OAuthConfig(
                clientID: "",
                authorizeURL: "https://auth.openai.com/authorize",
                tokenURL: "https://auth.openai.com/oauth/token",
                scopes: "openid profile offline_access",
                redirectURI: "com.sessionlimittracker://oauth",
                callbackScheme: "com.sessionlimittracker")
        case .gemini:
            return OAuthConfig(
                clientID: "",
                authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                scopes: "openid email https://www.googleapis.com/auth/cloud-platform.read-only",
                redirectURI: "com.sessionlimittracker://oauth",
                callbackScheme: "com.sessionlimittracker")
        }
    }
}

struct OAuthTokens: Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
}

enum OAuthError: LocalizedError {
    case missingClientID
    case badAuthorizeURL
    case noCode
    case stateMismatch
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID: return "Enter your OAuth client ID first."
        case .badAuthorizeURL: return "The authorize URL is invalid."
        case .noCode: return "No authorization code was returned."
        case .stateMismatch: return "OAuth state mismatch (possible tampering)."
        case .tokenExchangeFailed(let m): return "Token exchange failed: \(m)"
        }
    }
}

/// Full Authorization Code + PKCE OAuth via ASWebAuthenticationSession.
@MainActor
final class OAuthLoginFlow: NSObject, ASWebAuthenticationPresentationContextProviding {

    private var session: ASWebAuthenticationSession?

    /// Runs the OAuth flow. When `useSystemBrowser` is true (default) the authorize
    /// step happens in the user's real default browser via a localhost loopback
    /// redirect — reusing whatever account they're already logged into. Otherwise
    /// it uses an in-app secure web view that shares the Safari cookie store.
    func signIn(config: OAuthConfig, useSystemBrowser: Bool = true) async throws -> OAuthTokens {
        guard !config.clientID.trimmingCharacters(in: .whitespaces).isEmpty else { throw OAuthError.missingClientID }

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafe(24)

        if useSystemBrowser {
            return try await signInSystemBrowser(config: config, verifier: verifier, challenge: challenge, state: state)
        }

        // In-app secure web view (shares Safari login; not ephemeral).
        let authURL = try Self.authorizeURL(config: config, redirectURI: config.redirectURI, challenge: challenge, state: state)
        let callback = try await runSession(url: authURL, scheme: config.callbackScheme)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw OAuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw OAuthError.noCode }
        return try await exchange(code: code, verifier: verifier, config: config, redirectURI: config.redirectURI)
    }

    /// Default-browser loopback flow (RFC 8252).
    private func signInSystemBrowser(config: OAuthConfig, verifier: String, challenge: String, state: String) async throws -> OAuthTokens {
        let server = LoopbackOAuthServer()
        let port = try await server.start()
        let redirect = "http://127.0.0.1:\(port)/callback"
        do {
            let authURL = try Self.authorizeURL(config: config, redirectURI: redirect, challenge: challenge, state: state)
            NSWorkspace.shared.open(authURL)   // opens the user's default browser
            let code = try await server.awaitCode(expectedState: state)
            server.stop()
            return try await exchange(code: code, verifier: verifier, config: config, redirectURI: redirect)
        } catch {
            server.stop()
            throw error
        }
    }

    private static func authorizeURL(config: OAuthConfig, redirectURI: String, challenge: String, state: String) throws -> URL {
        guard var comps = URLComponents(string: config.authorizeURL) else { throw OAuthError.badAuthorizeURL }
        comps.queryItems = (comps.queryItems ?? []) + [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: config.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let url = comps.url else { throw OAuthError.badAuthorizeURL }
        return url
    }

    // MARK: - Web session

    private func runSession(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? URLError(.userCancelledAuthentication)) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false   // reuse the Safari login session
            self.session = s
            if !s.start() { cont.resume(throwing: URLError(.cannotConnectToHost)) }
        }
    }

    // MARK: - Token exchange

    private func exchange(code: String, verifier: String, config: OAuthConfig, redirectURI: String) async throws -> OAuthTokens {
        guard let url = URL(string: config.tokenURL) else { throw OAuthError.tokenExchangeFailed("bad token URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": config.clientID,
            "code_verifier": verifier
        ]
        req.httpBody = form.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw OAuthError.tokenExchangeFailed("HTTP \(code): \(String(data: data, encoding: .utf8) ?? "")")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("no access_token in response")
        }
        return OAuthTokens(accessToken: access,
                           refreshToken: obj["refresh_token"] as? String,
                           expiresIn: (obj["expires_in"] as? Int) ?? (obj["expires_in"] as? Double).map(Int.init))
    }

    // MARK: - Helpers

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return base64url(Data(bytes))
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
