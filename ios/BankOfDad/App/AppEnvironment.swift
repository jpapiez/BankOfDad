import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let vault: TokenVault
    let keychain: KeychainStore
    let apiClient: APIClient
    let authSession: AuthSession
    let router: AppRouter
    let pushManager: PushManager

    /// Services are swapped wholesale when demo mode is entered or exited, so every screen keeps
    /// talking to the same protocols and never needs to know which mode it is running in.
    private(set) var familyService: any FamilyService
    private(set) var loanService: any LoanService
    private(set) var billService: any BillService
    private(set) var notificationService: any NotificationService

    private let liveFamilyService: any FamilyService
    private let liveLoanService: any LoanService
    private let liveBillService: any BillService
    private let liveNotificationService: any NotificationService

    private(set) var demo: DemoSession?

    /// Screens ask the environment for this capability rather than checking service types.
    var isDemo: Bool { demo != nil }

    init() {
        let baseURL = Self.baseURLFromInfoPlist()
        let vault = TokenVault()
        let keychain = KeychainStore()
        UITestHooks.prepareKeychain(keychain)
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
        let family = LiveFamilyService(api: apiClient)
        let loans = LiveLoanService(api: apiClient)
        let bills = LiveBillService(api: apiClient)
        let notifications = LiveNotificationService(api: apiClient)
        self.liveFamilyService = family
        self.liveLoanService = loans
        self.liveBillService = bills
        self.liveNotificationService = notifications
        self.familyService = family
        self.loanService = loans
        self.billService = bills
        self.notificationService = notifications
        self.authSession = AuthSession(apiClient: apiClient, keychain: keychain, vault: vault)
        self.pushManager = PushManager(notificationService: notifications, router: self.router)
        authFailureHandler.session = self.authSession
    }

    // MARK: - Demo mode

    /// Starts (or re-enters) demo mode. No keychain entry is written and no request ever leaves the
    /// device: the services are replaced with local ones and the API client is hard-blocked.
    func enterDemo(role: Role, referenceDate: Date? = nil) async {
        let session: DemoSession
        if let existing = demo {
            session = existing
        } else {
            let store = DemoStore(referenceDate: referenceDate ?? DemoLaunchOptions.current.referenceDate ?? Date())
            session = DemoSession(store: store, role: role)
            demo = session
        }

        DemoIsolation.shared.setDemoActive(true)
        familyService = DemoFamilyService(store: session.store)
        loanService = DemoLoanService(store: session.store)
        billService = DemoBillService(store: session.store)
        notificationService = DemoNotificationService(store: session.store)

        await session.refresh()
        await session.apply(role: role, childId: session.activeChildId)
        await authSession.beginDemo(user: session.currentUser())
    }

    func switchDemoRole(to role: Role, childId: UUID? = nil) async {
        guard let session = demo else { return }
        await session.apply(role: role, childId: childId)
        await authSession.beginDemo(user: session.currentUser())
    }

    func resetDemoData() async {
        guard let session = demo else { return }
        await session.store.reset()
        await session.refresh()
        await session.apply(role: session.role, childId: session.activeChildId)
    }

    func exitDemo() async {
        guard demo != nil else { return }
        demo = nil
        familyService = liveFamilyService
        loanService = liveLoanService
        billService = liveBillService
        notificationService = liveNotificationService
        DemoIsolation.shared.setDemoActive(false)
        await authSession.endDemo()
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
