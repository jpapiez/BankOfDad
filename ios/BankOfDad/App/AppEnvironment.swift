import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    private(set) var vault: TokenVault
    let keychain: KeychainStore
    private(set) var apiClient: APIClient
    private(set) var authSession: AuthSession
    let router: AppRouter
    private(set) var pushManager: PushManager
    private(set) var serverProfile: ServerProfile?

    private(set) var familyService: any FamilyService
    private(set) var loanService: any LoanService
    private(set) var billService: any BillService
    private(set) var notificationService: any NotificationService

    private var liveFamilyService: any FamilyService
    private var liveLoanService: any LoanService
    private var liveBillService: any BillService
    private var liveNotificationService: any NotificationService

    private(set) var demo: DemoSession?
    var isDemo: Bool { demo != nil }

    init() {
        let keychain = KeychainStore()
        let router = AppRouter()
        UITestHooks.prepareKeychain(keychain)
        let storedProfile = try? keychain.loadProfile()
        let legacyTokens = storedProfile == nil
            ? (try? keychain.loadLegacyTokens()) ?? UITestHooks.launchTokens
            : nil
        let profile = storedProfile ?? Self.seedProfileFromInfoPlist(hasLegacyTokens: legacyTokens != nil)

        if storedProfile == nil, let profile {
            try? keychain.save(session: .init(profile: profile, tokens: legacyTokens))
        }

        let components = Self.makeLiveComponents(
            profile: profile,
            keychain: keychain,
            router: router
        )
        self.keychain = keychain
        self.router = router
        self.serverProfile = profile
        self.vault = components.vault
        self.apiClient = components.apiClient
        self.authSession = components.authSession
        self.pushManager = components.pushManager
        self.liveFamilyService = components.family
        self.liveLoanService = components.loans
        self.liveBillService = components.bills
        self.liveNotificationService = components.notifications
        self.familyService = components.family
        self.loanService = components.loans
        self.billService = components.bills
        self.notificationService = components.notifications
    }

    func bootstrap() async {
        guard let profile = serverProfile else {
            authSession.markNeedsServer()
            return
        }

        do {
            let expectedID = profile.id == Self.legacyServerID ? nil : profile.id
            let descriptor = try await ServerDiscoveryClient().discover(origin: profile.origin, expectedServerID: expectedID)
            let verified = try ServerProfile(descriptor: descriptor)
            let tokens = try? keychain.loadTokens()
            try keychain.save(session: .init(profile: verified, tokens: tokens))
            replaceLive(with: verified)
        } catch {
            authSession.markUnavailable(error.localizedDescription)
            return
        }
        await authSession.bootstrap()
    }

    func configureServer(_ profile: ServerProfile) throws {
        guard !isDemo else { throw ServerConnectionError.invalidResponse }
        try keychain.save(profile: profile)
        replaceLive(with: profile)
        authSession.markSignedOut()
    }

    func switchServer(to profile: ServerProfile) async throws {
        guard !isDemo else { throw ServerConnectionError.invalidResponse }
        if case .authenticated = authSession.state {
            await authSession.logout()
        }
        try keychain.deleteTokens()
        try keychain.save(profile: profile)
        replaceLive(with: profile)
        authSession.markSignedOut()
    }

    func forgetServer() async {
        if isDemo { await exitDemo() }
        if case .authenticated = authSession.state {
            await authSession.logout()
        }
        try? keychain.deleteTokens()
        replaceLive(with: nil)
        authSession.markNeedsServer()
    }

    // MARK: - Demo mode

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

    private func replaceLive(with profile: ServerProfile?) {
        let components = Self.makeLiveComponents(profile: profile, keychain: keychain, router: router)
        serverProfile = profile
        vault = components.vault
        apiClient = components.apiClient
        authSession = components.authSession
        pushManager = components.pushManager
        liveFamilyService = components.family
        liveLoanService = components.loans
        liveBillService = components.bills
        liveNotificationService = components.notifications
        if !isDemo {
            familyService = components.family
            loanService = components.loans
            billService = components.bills
            notificationService = components.notifications
        }
    }

    private static func makeLiveComponents(
        profile: ServerProfile?,
        keychain: KeychainStore,
        router: AppRouter
    ) -> (
        vault: TokenVault,
        apiClient: APIClient,
        authSession: AuthSession,
        pushManager: PushManager,
        family: any FamilyService,
        loans: any LoanService,
        bills: any BillService,
        notifications: any NotificationService
    ) {
        let vault = TokenVault()
        let authFailureHandler = AuthFailureHandler()
        let apiClient = APIClient(
            baseURL: profile?.origin ?? URL(string: "http://localhost:8080")!,
            vault: vault,
            onAuthFailed: { await authFailureHandler.signOut() },
            onTokensRefreshed: { auth in
                try? keychain.save(tokens: .init(accessToken: auth.accessToken, refreshToken: auth.refreshToken))
            }
        )
        let family = LiveFamilyService(api: apiClient)
        let loans = LiveLoanService(api: apiClient)
        let bills = LiveBillService(api: apiClient)
        let notifications = LiveNotificationService(api: apiClient)
        let authSession = AuthSession(apiClient: apiClient, keychain: keychain, vault: vault, serverConfigured: profile != nil)
        let pushManager = PushManager(notificationService: notifications, router: router, supportsPush: profile?.capabilities.push == true)
        authFailureHandler.session = authSession
        return (vault, apiClient, authSession, pushManager, family, loans, bills, notifications)
    }

    private static let legacyServerID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private static func seedProfileFromInfoPlist(hasLegacyTokens: Bool) -> ServerProfile? {
        #if !DEBUG
        guard hasLegacyTokens else { return nil }
        #endif
        guard let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
              let origin = try? ServerOriginPolicy.validate(value) else {
            return nil
        }
        return ServerProfile(id: legacyServerID, origin: origin, familyName: nil, capabilities: .legacy, childPin: .standard)
    }
}

@MainActor
private final class AuthFailureHandler {
    weak var session: AuthSession?

    func signOut() async {
        await session?.signOutLocal()
    }
}
