import Foundation
import Security

final class KeychainStore: @unchecked Sendable {
    struct StoredTokens: Codable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String
    }

    private let service = "com.example.bankofdad.auth"
    private let account = "tokens"

    func save(tokens: StoredTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        var query = baseQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func loadTokens() throws -> StoredTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return try JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func deleteTokens() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? { "Keychain error \(statusCode)" }
        private var statusCode: OSStatus {
            switch self { case .status(let status): return status }
        }
    }
}
