import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case loading
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
    var errorMessage: String?

    init(apiClient: APIClient, keychain: KeychainStore, vault: TokenVault) {
        self.apiClient = apiClient
        self.keychain = keychain
        self.vault = vault
    }

    func bootstrap() async {
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

    func signInWithApple(identityToken: String, displayName: String?, familyName: String?, timeZone: String?, inviteCode: String?) async {
        await authenticate {
            try await self.apiClient.post("/auth/apple", body: AppleAuthRequest(identityToken: identityToken, displayName: displayName, familyName: familyName, timeZone: timeZone, inviteCode: inviteCode.map(PairingCode.normalized)), requiresAuth: false)
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

    func logout() async {
        let tokens = await vault.tokens()
        let refresh = tokens.refresh
        if let refresh {
            try? await apiClient.sendNoResponse("POST", path: "/auth/logout", body: LogoutRequest(refreshToken: refresh), requiresAuth: false)
        }
        await signOutLocal()
    }

    func signOutLocal() async {
        try? keychain.deleteTokens()
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
struct AppleAuthRequest: Encodable { let identityToken: String; let displayName: String?; let familyName: String?; let timeZone: String?; let inviteCode: String? }
struct PairRequest: Encodable { let code: String; let deviceName: String }
struct AcceptInviteRequest: Encodable { let inviteCode: String; let email: String; let password: String; let displayName: String }
struct LogoutRequest: Encodable { let refreshToken: String }
