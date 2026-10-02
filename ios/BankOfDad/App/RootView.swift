import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingDemoOptions = false

    var body: some View {
        let authSession = environment.authSession
        Group {
            switch authSession.state {
            case .loading:
                LoadingView(message: "Opening the vault…")
            case .needsServer:
                NavigationStack { ServerRequiredView() }
            case .signedOut:
                NavigationStack {
                    if let enrollment = environment.router.pendingEnrollment {
                        EnrollmentDestinationView(enrollment: enrollment)
                    } else {
                        WelcomeView()
                    }
                }
                .id(environment.router.pendingEnrollment?.token ?? "welcome")
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if environment.isDemo {
                DemoBanner { showingDemoOptions = true }
            }
        }
        .sheet(isPresented: $showingDemoOptions) { DemoOptionsSheet() }
        .onChange(of: environment.isDemo) { _, isDemo in
            if !isDemo { showingDemoOptions = false }
        }
        .task(id: authSession.currentUser?.id) {
            guard authSession.currentUser != nil else { return }
            // A pairing link only applies to a signed-out device, so never let one linger past sign-in
            // (it would otherwise auto-pair on the next sign-out).
            environment.router.pendingPairingCode = nil
            environment.router.pendingServerConnection = nil
            environment.router.pendingEnrollment = nil
            // Demo mode is offline and must never raise the system push prompt.
            guard !environment.isDemo else { return }
            await environment.pushManager.requestAuthorizationAndRegister()
        }
    }
}
