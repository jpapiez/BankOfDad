import SwiftUI

struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AppRouter.self) private var router
    @State private var showingServerConnection = false

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
                Text(environment.serverProfile?.familyName ?? "A friendly family ledger for loans, reminders, receipts, and payback progress.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                if let origin = environment.serverProfile?.origin {
                    Label(origin.host ?? origin.absoluteString, systemImage: origin.scheme == "https" ? "lock.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(origin.scheme == "https" ? Color.secondary : Color.orange)
                }
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

                NavigationLink { ChildSignInView() } label: {
                    Label("I'm a Kid", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Theme.kidAccent)
                .accessibilityIdentifier("welcome.kid")

                Button {
                    showingServerConnection = true
                } label: {
                    Label("Scan an Invitation", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("welcome.invitation")

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
        .sheet(isPresented: $showingServerConnection) {
            NavigationStack {
                ConnectServerView()
                    .padding()
                    .navigationTitle("Connect Server")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showingServerConnection = false }
                        }
                    }
            }
        }
        .onAppear(perform: consumePendingConnection)
        .onChange(of: router.pendingServerConnection) { _, _ in consumePendingConnection() }
        .onChange(of: router.pendingEnrollment) { _, enrollment in
            if enrollment != nil {
                showingServerConnection = false
            }
        }
    }

    private func consumePendingConnection() {
        if router.pendingServerConnection != nil {
            showingServerConnection = true
        }
    }
}

#Preview { NavigationStack { WelcomeView() }.environment(AppEnvironment()).environment(AppRouter()) }
