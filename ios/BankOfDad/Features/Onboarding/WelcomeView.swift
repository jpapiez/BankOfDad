import SwiftUI

struct WelcomeView: View {
    @Environment(AppRouter.self) private var router
    @State private var showingKidPairing = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "banknote.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(Theme.bankAccent)
                    .accessibilityHidden(true)
                Text("Bank of Dad")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A friendly family ledger for loans, reminders, receipts, and payback progress.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            VStack(spacing: 14) {
                NavigationLink { ParentSignInView() } label: {
                    Label("I'm the Bank", systemImage: "person.2.badge.gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.bankAccent)
                .accessibilityIdentifier("welcome.parent")

                Button { showingKidPairing = true } label: {
                    Label("I'm a Kid", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Theme.kidAccent)
                .accessibilityIdentifier("welcome.kid")

                NavigationLink { DemoEntryView() } label: {
                    Label("Explore Demo", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("welcome.demo")
                .accessibilityHint("Explore the app with sample data. No account is needed.")
            }
            .padding(.horizontal)
            Spacer()
        }
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showingKidPairing) { KidPairingView() }
        // A pairing link (e.g. the parent's QR code opened by the Camera app) jumps straight to pairing.
        .onAppear { if router.pendingPairingCode != nil { showingKidPairing = true } }
        .onChange(of: router.pendingPairingCode) { _, newValue in
            if newValue != nil { showingKidPairing = true }
        }
    }
}

#Preview { NavigationStack { WelcomeView() }.environment(AppRouter()) }
