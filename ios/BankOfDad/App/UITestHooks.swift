import Foundation

/// Launch-time switches used by the XCUITest suite (`BankOfDadUITests`).
///
/// Everything here is inert unless the app is a Debug build launched with the `-UITests` argument,
/// so normal runs (and Release builds) never honor these values.
enum UITestHooks {
    static let launchArgument = "-UITests"
    static let resetKeychainArgument = "-UITestsResetKeychain"
    static let accessTokenKey = "UITESTS_ACCESS_TOKEN"
    static let refreshTokenKey = "UITESTS_REFRESH_TOKEN"

    static var isActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains(launchArgument)
        #else
        return false
        #endif
    }

    /// The system notification permission alert would block UI automation.
    static var skipPushRegistration: Bool { isActive }

    static var launchTokens: KeychainStore.StoredTokens? {
        guard isActive else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let access = environment[accessTokenKey],
              let refresh = environment[refreshTokenKey],
              !access.isEmpty,
              !refresh.isEmpty else {
            return nil
        }
        return .init(accessToken: access, refreshToken: refresh)
    }

    /// Call before `AuthSession.bootstrap()`: clears stored tokens and optionally seeds a session.
    static func prepareKeychain(_ keychain: KeychainStore) {
        guard isActive else { return }
        let process = ProcessInfo.processInfo
        if process.arguments.contains(resetKeychainArgument) { try? keychain.deleteTokens() }
        if let tokens = launchTokens {
            try? keychain.save(tokens: tokens)
        }
    }
}
