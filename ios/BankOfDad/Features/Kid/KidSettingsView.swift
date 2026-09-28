import SwiftUI

@MainActor
struct KidSettingsView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        Form {
            Section("Account") {
                if let user = authSession.currentUser {
                    LabeledContent("Name", value: user.displayName)
                    Text("If something looks wrong, ask the Bank to update it from Family settings.")
                        .foregroundStyle(.secondary)
                }
            }
            Section { Button("Sign out", role: .destructive) { Task { await authSession.logout() } } }
        }
        .navigationTitle("Settings")
    }
}
