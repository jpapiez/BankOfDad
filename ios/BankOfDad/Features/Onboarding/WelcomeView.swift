import SwiftUI

struct WelcomeView: View {
    @State private var path = NavigationPath()

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

                NavigationLink { KidPairingView() } label: {
                    Label("I'm a Kid", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Theme.kidAccent)
            }
            .padding(.horizontal)
            Spacer()
        }
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview { NavigationStack { WelcomeView() } }
