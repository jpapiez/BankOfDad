import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let vault: TokenVault
    let keychain: KeychainStore
    let apiClient: APIClient
    let familyService: FamilyService
    let loanService: LoanService
    let notificationService: NotificationService
    let authSession: AuthSession
    let router: AppRouter
    let pushManager: PushManager

    init() {
        let baseURL = Self.baseURLFromInfoPlist()
        let vault = TokenVault()
        let keychain = KeychainStore()
        let authFailureHandler = AuthFailureHandler()
        self.vault = vault
        self.keychain = keychain
        self.router = AppRouter()
        let apiClient = APIClient(baseURL: baseURL, vault: vault, onAuthFailed: {
            await authFailureHandler.signOut()
        }, onTokensRefreshed: { auth in
            try? keychain.save(tokens: .init(accessToken: auth.accessToken, refreshToken: auth.refreshToken))
        })
        self.apiClient = apiClient
        self.familyService = FamilyService(api: apiClient)
        self.loanService = LoanService(api: apiClient)
        self.notificationService = NotificationService(api: apiClient)
        self.authSession = AuthSession(apiClient: apiClient, keychain: keychain, vault: vault)
        self.pushManager = PushManager(notificationService: self.notificationService, router: self.router)
        authFailureHandler.session = self.authSession
    }

    private static func baseURLFromInfoPlist() -> URL {
        let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
        return URL(string: value ?? "http://localhost:8080") ?? URL(string: "http://localhost:8080")!
    }
}

@MainActor
private final class AuthFailureHandler {
    weak var session: AuthSession?

    func signOut() async {
        await session?.signOutLocal()
    }
}
