import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var family: FamilyDto?
    var name = ""
    var timeZone = TimeZone.current.identifier
    var error: String?

    func load(service: any FamilyService) async {
        do { family = try await service.family(); name = family?.name ?? ""; timeZone = family?.timeZone ?? TimeZone.current.identifier; error = nil }
        catch { self.error = error.localizedDescription }
    }

    func save(service: any FamilyService) async {
        do { family = try await service.updateFamily(name: name, timeZone: timeZone); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    private var authSession: AuthSession { environment.authSession }
    @State private var viewModel = SettingsViewModel()
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section("Account") {
                if let user = authSession.currentUser {
                    LabeledContent("Name", value: user.displayName)
                        .accessibilityIdentifier("settings.name")
                    if let email = user.email { LabeledContent("Email", value: email).accessibilityIdentifier("settings.email") }
                    LabeledContent("Role", value: user.role.rawValue)
                        .accessibilityIdentifier("settings.role")
                }
            }
            Section("Family") {
                TextField("Family name", text: $viewModel.name)
                    .accessibilityIdentifier("settings.familyName")
                TextField("Time zone", text: $viewModel.timeZone)
                    .accessibilityIdentifier("settings.timeZone")
                Button("Save changes") { Task { await viewModel.save(service: environment.familyService) } }
                    .accessibilityIdentifier("settings.save")
            }
            if environment.isDemo {
                DemoSettingsSection()
            } else {
                ServerSettingsSection()
                Section("Danger zone") {
                    Button("Delete My Account", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                    .accessibilityIdentifier("settings.deleteAccount")
                    Text("This permanently deletes your parent account. If you are the last parent, the family's children, loans, bills, payments, notifications, and device access are deleted too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section { Button("Sign out", role: .destructive) { Task { await authSession.logout() } }.accessibilityIdentifier("settings.signOut") }
            }
        }
        .navigationTitle("Settings")
        .task { await viewModel.load(service: environment.familyService) }
        .confirmationDialog("Delete your account?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete My Account", role: .destructive) {
                Task {
                    do {
                        try await authSession.deleteAccount()
                    } catch {
                        viewModel.error = error.localizedDescription
                    }
                }
            }
            .accessibilityIdentifier("settings.confirmDelete")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Your sign-in credentials, sessions, and Sign in with Apple authorization (if used) will be revoked. If you are the last parent, all private family data will be permanently deleted.")
        }
    }
}
