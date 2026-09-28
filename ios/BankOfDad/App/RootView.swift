import SwiftUI

struct RootView: View {
    @Environment(AuthSession.self) private var authSession
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Group {
            switch authSession.state {
            case .loading:
                LoadingView(message: "Opening the vault…")
            case .signedOut:
                NavigationStack { WelcomeView() }
            case .unavailable(let message):
                VStack(spacing: 16) {
                    EmptyStateView(systemImage: "wifi.exclamationmark", title: "Can't reach the Bank", message: message)
                    Button("Try again") { Task { await authSession.bootstrap() } }
                        .buttonStyle(.borderedProminent)
                    Button("Sign out", role: .destructive) { Task { await authSession.signOutLocal() } }
                }
                .padding()
            case .authenticated(let user):
                if user.role == .parent { ParentRootView() } else { KidRootView() }
            }
        }
        .task(id: authSession.currentUser?.id) {
            guard authSession.currentUser != nil else { return }
            // A pairing link only applies to a signed-out device, so never let one linger past sign-in
            // (it would otherwise auto-pair on the next sign-out).
            environment.router.pendingPairingCode = nil
            await environment.pushManager.requestAuthorizationAndRegister()
        }
    }
}
