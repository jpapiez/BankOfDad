import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsViewModel {
    var family: FamilyDto?
    var name = ""
    var timeZone = TimeZone.current.identifier
    var error: String?

    func load(service: FamilyService) async {
        do { family = try await service.family(); name = family?.name ?? ""; timeZone = family?.timeZone ?? TimeZone.current.identifier; error = nil }
        catch { self.error = error.localizedDescription }
    }

    func save(service: FamilyService) async {
        do { family = try await service.updateFamily(name: name, timeZone: timeZone); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(AuthSession.self) private var authSession
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section("Account") {
                if let user = authSession.currentUser {
                    LabeledContent("Name", value: user.displayName)
                    if let email = user.email { LabeledContent("Email", value: email) }
                    LabeledContent("Role", value: user.role.rawValue)
                }
            }
            Section("Family") {
                TextField("Family name", text: $viewModel.name)
                TextField("Time zone", text: $viewModel.timeZone)
                Button("Save changes") { Task { await viewModel.save(service: environment.familyService) } }
            }
            Section { Button("Sign out", role: .destructive) { Task { await authSession.logout() } } }
        }
        .navigationTitle("Settings")
        .task { await viewModel.load(service: environment.familyService) }
    }
}
