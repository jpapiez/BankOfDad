import Foundation
import Security

final class KeychainStore: @unchecked Sendable {
    struct StoredTokens: Codable, Equatable, Sendable {
        let accessToken: String
        let refreshToken: String
    }

    struct StoredSession: Codable, Equatable, Sendable {
        let profile: ServerProfile
        let tokens: StoredTokens?
    }

    private let service = "com.example.bankofdad.auth"
    private let account = "tokens"

    func save(tokens: StoredTokens) throws {
        guard let profile = try loadSession()?.profile else { throw KeychainError.missingServerProfile }
        try save(session: StoredSession(profile: profile, tokens: tokens))
    }

    func save(profile: ServerProfile) throws {
        try save(session: StoredSession(profile: profile, tokens: nil))
    }

    func loadProfile() throws -> ServerProfile? {
        try loadSession()?.profile
    }

    func save(session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        var query = baseQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func loadTokens() throws -> StoredTokens? {
        try loadSession()?.tokens
    }

    func loadSession() throws -> StoredSession? {
        guard let data = try loadData() else { return nil }
        return try JSONDecoder().decode(StoredSession.self, from: data)
    }

    func loadLegacyTokens() throws -> StoredTokens? {
        guard let data = try loadData() else { return nil }
        return try? JSONDecoder().decode(StoredTokens.self, from: data)
    }

    func deleteTokens() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    func clearTokens() throws {
        guard let profile = try loadSession()?.profile else {
            try deleteTokens()
            return
        }
        try save(session: StoredSession(profile: profile, tokens: nil))
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func loadData() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return data
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        case missingServerProfile
        var errorDescription: String? {
            switch self {
            case .status: "Keychain error \(statusCode)"
            case .missingServerProfile: "A family server must be configured before saving credentials."
            }
        }
        private var statusCode: OSStatus {
            switch self {
            case .status(let status): return status
            case .missingServerProfile: return errSecParam
            }
        }
    }
}
