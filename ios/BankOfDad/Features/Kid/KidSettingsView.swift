import SwiftUI

@MainActor
struct KidSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }

    var body: some View {
        Form {
            Section("Account") {
                if let user = authSession.currentUser {
                    LabeledContent("Name", value: user.displayName)
                        .accessibilityIdentifier("kidSettings.name")
                    Text("If something looks wrong, ask the Bank to update it from Family settings.")
                        .foregroundStyle(.secondary)
                }
            }
            if environment.isDemo {
                DemoSettingsSection()
            } else {
                ServerSettingsSection()
                Section { Button("Sign out", role: .destructive) { Task { await authSession.logout() } }.accessibilityIdentifier("kidSettings.signOut") }
            }
        }
        .navigationTitle("Settings")
    }
}
