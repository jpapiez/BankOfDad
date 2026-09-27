import Foundation
import Observation
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppRouter {
    var selectedLoanID: UUID?
    var pendingPairingCode: String?

    func handle(url: URL) {
        guard url.scheme == "bankofdad", url.host == "pair" else { return }
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            pendingPairingCode = PairingCode.normalized(code)
        }
    }
}

@MainActor
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static weak var shared: PushManager?
    private let notificationService: NotificationService
    private let router: AppRouter
    private var latestToken: String?

    init(notificationService: NotificationService, router: AppRouter) {
        self.notificationService = notificationService
        self.router = router
        super.init()
        UNUserNotificationCenter.current().delegate = self
        PushManager.shared = self
    }

    func requestAuthorizationAndRegister() async {
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
