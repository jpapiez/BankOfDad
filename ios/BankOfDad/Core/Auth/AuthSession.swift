import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case loading
        case needsServer
        case signedOut
        case unavailable(String)
        case authenticated(UserDto)
    }

    private let apiClient: APIClient
    private let keychain: KeychainStore
    private let vault: TokenVault

    private(set) var state: State = .loading
    private(set) var currentUser: UserDto?
    private(set) var isAuthenticating = false
    /// True while the app is exploring sample data. Demo sessions never read or write the keychain.
    private(set) var isDemo = false
    var errorMessage: String?

    init(apiClient: APIClient, keychain: KeychainStore, vault: TokenVault, serverConfigured: Bool = true) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.vault = vault
        if !serverConfigured { state = .needsServer }
    }

    func bootstrap() async {
        guard (try? keychain.loadProfile()) != nil else {
            state = .needsServer
            return
        }
        state = .loading
        do {
            if let stored = try keychain.loadTokens() {
                await vault.update(accessToken: stored.accessToken, refreshToken: stored.refreshToken)
                let user: UserDto = try await apiClient.get("/auth/me")
                currentUser = user
                state = .authenticated(user)
            } else {
                state = .signedOut
            }
        } catch APIError.unauthorized {
            await signOutLocal()
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    func markNeedsServer() {
        currentUser = nil
        errorMessage = nil
        state = .needsServer
    }

    func markSignedOut() {
        currentUser = nil
        errorMessage = nil
        state = .signedOut
    }

    func markUnavailable(_ message: String) {
        currentUser = nil
        errorMessage = message
        state = .unavailable(message)
    }

    func register(email: String, password: String, displayName: String, familyName: String, timeZone: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/register", body: RegisterRequest(email: email, password: password, displayName: displayName, familyName: familyName, timeZone: timeZone), requiresAuth: false)
        }
    }

    func login(email: String, password: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/login", body: LoginRequest(email: email, password: password), requiresAuth: false)
        }
    }

    func signInWithApple(identityToken: String, authorizationCode: String, displayName: String?, familyName: String?, timeZone: String?, inviteCode: String?) async {
        await authenticate {
            try await self.apiClient.post("/auth/apple", body: AppleAuthRequest(identityToken: identityToken, authorizationCode: authorizationCode, displayName: displayName, familyName: familyName, timeZone: timeZone, inviteCode: inviteCode.map(PairingCode.normalized)), requiresAuth: false)
        }
    }

    func pair(code: String, deviceName: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/pair", body: PairRequest(code: PairingCode.normalized(code), deviceName: deviceName), requiresAuth: false)
        }
    }

    func acceptInvite(inviteCode: String, email: String, password: String, displayName: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/accept-invite", body: AcceptInviteRequest(inviteCode: PairingCode.normalized(inviteCode), email: email, password: password, displayName: displayName), requiresAuth: false)
        }
    }

    func acceptEnrollment(token: String, email: String, password: String, displayName: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/accept-enrollment", body: AcceptInviteRequest(inviteCode: token, email: email, password: password, displayName: displayName), requiresAuth: false)
        }
    }

    func completeBootstrap(token: String, email: String, password: String, displayName: String, familyName: String, timeZone: String) async {
        await authenticate {
            try await self.apiClient.post("/setup/complete", body: BootstrapCompleteRequest(token: token, email: email, password: password, displayName: displayName, familyName: familyName, timeZone: timeZone), requiresAuth: false)
        }
    }

    func completeChildEnrollment(token: String, username: String, secret: String, credentialKind: ChildCredentialKind, deviceName: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/complete-child-enrollment", body: ChildEnrollmentRequest(token: token, username: username, secret: secret, credentialKind: credentialKind, deviceName: deviceName), requiresAuth: false)
        }
    }

    func loginChild(username: String, secret: String, deviceName: String) async {
        await authenticate {
            try await self.apiClient.post("/auth/child-login", body: ChildLoginRequest(username: username, secret: secret, deviceName: deviceName), requiresAuth: false)
        }
    }

    func logout() async {
        if isDemo {
            await endDemo()
            return
        }
        let tokens = await vault.tokens()
        let refresh = tokens.refresh
        if let refresh {
            try? await apiClient.sendNoResponse("POST", path: "/auth/logout", body: LogoutRequest(refreshToken: refresh), requiresAuth: false)
        }
        await signOutLocal()
    }

    func deleteAccount() async throws {
        try await apiClient.deleteAccount()
        await signOutLocal()
    }

    /// Signs the UI into a sample identity without ever touching the keychain or the token vault.
    func beginDemo(user: UserDto) async {
        isDemo = true
        errorMessage = nil
        currentUser = user
        state = .authenticated(user)
    }

    /// Leaves demo mode and returns to the signed-out screen, again without touching stored tokens.
    func endDemo() async {
        isDemo = false
        currentUser = nil
        errorMessage = nil
        state = .signedOut
    }

    func signOutLocal() async {
        if isDemo {
            await endDemo()
            return
        }
        try? keychain.clearTokens()
        await vault.clear()
        currentUser = nil
        state = .signedOut
    }

    private func authenticate(_ operation: () async throws -> AuthResponse) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        errorMessage = nil
        do {
            let auth = try await operation()
            try keychain.save(tokens: .init(accessToken: auth.accessToken, refreshToken: auth.refreshToken))
            await vault.update(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
            currentUser = auth.user
            errorMessage = nil
            state = .authenticated(auth.user)
        } catch {
            errorMessage = error.localizedDescription
            state = .signedOut
        }
    }
}

struct RegisterRequest: Encodable { let email: String; let password: String; let displayName: String; let familyName: String; let timeZone: String }
struct LoginRequest: Encodable { let email: String; let password: String }
struct AppleAuthRequest: Encodable { let identityToken: String; let authorizationCode: String; let displayName: String?; let familyName: String?; let timeZone: String?; let inviteCode: String? }
struct PairRequest: Encodable { let code: String; let deviceName: String }
struct AcceptInviteRequest: Encodable { let inviteCode: String; let email: String; let password: String; let displayName: String }
struct LogoutRequest: Encodable { let refreshToken: String }
