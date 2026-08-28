import Foundation
import Security

/// Keychain-backed secret store — the native equivalent of OmniRoute's encrypted-
/// at-rest credential vault. Secrets are read per-request and never written to
/// UserDefaults, logs, or disk by the app. Safe (returns nil / no-ops) when the
/// Keychain is unavailable.
struct CredentialVault: Sendable {

    private let service = "com.sessionlimittracker.credentials"

    private func account(_ id: ProviderID, _ method: ConnectionMethod) -> String {
        "\(id.rawValue).\(method.rawValue)"
    }

    @discardableResult
    func store(_ secret: String, for id: ProviderID, method: ConnectionMethod) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        let acct = account(id, method)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    func read(for id: ProviderID, method: ConnectionMethod) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(id, method),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func delete(for id: ProviderID, method: ConnectionMethod) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(id, method)
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func hasCredential(for id: ProviderID, method: ConnectionMethod) -> Bool {
        read(for: id, method: method) != nil
    }
}
