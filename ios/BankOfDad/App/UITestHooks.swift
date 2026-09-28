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

    /// Call before `AuthSession.bootstrap()`: clears stored tokens and optionally seeds a session.
    static func prepareKeychain(_ keychain: KeychainStore) {
        guard isActive else { return }
        let process = ProcessInfo.processInfo
        if process.arguments.contains(resetKeychainArgument) { try? keychain.deleteTokens() }
        if let access = process.environment[accessTokenKey], let refresh = process.environment[refreshTokenKey], !access.isEmpty, !refresh.isEmpty {
            try? keychain.save(tokens: .init(accessToken: access, refreshToken: refresh))
        }
    }
}
