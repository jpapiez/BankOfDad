import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppRouter {
    var selectedLoanID: UUID?
    var pendingPairingCode: String?
    var pendingServerConnection: ServerConnectionLink?
    var pendingEnrollment: PendingEnrollment?

    func handle(url: URL) {
        if let connection = try? ServerConnectionLink(scannedValue: url.absoluteString) {
            pendingServerConnection = connection
            return
        }

        guard url.scheme == "bankofdad", url.host == "pair" else { return }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            pendingPairingCode = PairingCode.normalized(code)
        }

    }
}

struct PendingEnrollment: Equatable {
    let kind: EnrollmentKind
    let token: String
    let preview: EnrollmentPreview
}

@MainActor
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static weak var shared: PushManager?
    private let notificationService: any NotificationService
    private let router: AppRouter
    private let supportsPush: Bool
    private var latestToken: String?

    init(notificationService: any NotificationService, router: AppRouter, supportsPush: Bool = true) {
        self.notificationService = notificationService
        self.router = router
        self.supportsPush = supportsPush
        super.init()
        UNUserNotificationCenter.current().delegate = self
        PushManager.shared = self
    }

    func requestAuthorizationAndRegister() async {
        guard !UITestHooks.skipPushRegistration else { return }
        guard supportsPush else { return }
        // Demo mode must never show the system push prompt or register a device.
        guard !DemoIsolation.shared.isDemoActive else { return }
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        } catch { }
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        latestToken = token
        do { try await notificationService.registerDevice(apnsToken: token, environment: environmentName) } catch { }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) { }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .badge, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        if let loanIdString = userInfo["loanId"] as? String, let loanId = UUID(uuidString: loanIdString) {
            router.selectedLoanID = loanId
        }
    }

    private var environmentName: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
