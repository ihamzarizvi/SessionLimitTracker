import Foundation
import Network

/// Minimal localhost HTTP listener for the OAuth loopback redirect (RFC 8252).
/// Lets us run the authorize step in the user's real default browser — reusing
/// their already-logged-in session — and catch the `code` on 127.0.0.1.
final class LoopbackOAuthServer: @unchecked Sendable {

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.sessionlimittracker.oauth.loopback")
    private var continuation: CheckedContinuation<String, Error>?
    private var expectedState = ""
    private var didResumeStart = false

    /// Starts listening on an ephemeral loopback port and returns that port.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            do {
                let listener = try NWListener(using: .tcp, on: .any)
                self.listener = listener
                listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    self.queue.async {
                        guard !self.didResumeStart else { return }
                        switch state {
                        case .ready:
                            self.didResumeStart = true
                            cont.resume(returning: listener.port?.rawValue ?? 0)
                        case .failed(let error):
                            self.didResumeStart = true
                            cont.resume(throwing: error)
                        default:
                            break
                        }
                    }
                }
                listener.start(queue: queue)
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Awaits the browser redirect carrying the authorization code.
    func awaitCode(expectedState: String, timeout: TimeInterval = 300) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async {
                self.expectedState = expectedState
                self.continuation = cont
            }
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let c = self.continuation else { return }
                self.continuation = nil
                c.resume(throwing: URLError(.timedOut))
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self else { conn.cancel(); return }
            guard let data, let text = String(data: data, encoding: .utf8),
                  let requestLine = text.split(separator: "\r\n").first,
                  let pathPart = requestLine.split(separator: " ").dropFirst().first,
                  let comps = URLComponents(string: "http://127.0.0.1\(pathPart)") else {
                conn.cancel(); return
            }
            let items = comps.queryItems ?? []
            let code = items.first { $0.name == "code" }?.value
            let state = items.first { $0.name == "state" }?.value

            let body = "<html><body style=\"font-family:-apple-system;padding:40px;text-align:center\"><h3>Signed in.</h3><p>You can close this tab and return to Session Limit Tracker.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })

            self.finish(code: code, state: state)
        }
    }

    private func finish(code: String?, state: String?) {
        guard let cont = continuation else { return }
        continuation = nil
        if state != expectedState {
            cont.resume(throwing: OAuthError.stateMismatch)
        } else if let code {
            cont.resume(returning: code)
        } else {
            cont.resume(throwing: OAuthError.noCode)
        }
    }
}
