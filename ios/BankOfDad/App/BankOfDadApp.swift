import SwiftUI

@main
@MainActor
struct BankOfDadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .environment(environment.authSession)
                .environment(environment.router)
                .task {
                    let demoOptions = DemoLaunchOptions.current
                    if demoOptions.isEnabled {
                        await environment.enterDemo(role: demoOptions.role, referenceDate: demoOptions.referenceDate)
                        return
                    }
                    await environment.authSession.bootstrap()
                }
                .onOpenURL { url in
                    // Pairing links are ignored while someone is signed in or exploring the demo.
                    if environment.isDemo { return }
                    if case .authenticated = environment.authSession.state { return }
                    environment.router.handle(url: url)
                }
        }
    }
}
