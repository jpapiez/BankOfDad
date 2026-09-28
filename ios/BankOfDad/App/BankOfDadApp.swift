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
                .task { await environment.authSession.bootstrap() }
                .onOpenURL { url in
                    // Pairing links are ignored while someone is signed in.
                    if case .authenticated = environment.authSession.state { return }
                    environment.router.handle(url: url)
                }
        }
    }
}
