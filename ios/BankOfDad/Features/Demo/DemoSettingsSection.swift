import SwiftUI

/// Settings controls shown instead of "Sign out" while exploring the demo.
struct DemoSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingOptions = false

    var body: some View {
        Section {
            Button {
                showingOptions = true
            } label: {
                Label("Demo options", systemImage: "sparkles")
            }
            .accessibilityIdentifier("settings.demoOptions")

            Button(role: .destructive) {
                Task { await environment.exitDemo() }
            } label: {
                Label("Exit demo", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .accessibilityIdentifier("settings.exitDemo")
        } header: {
            Text("Demo")
        } footer: {
            Text("You're exploring sample data stored on this device. Nothing here is connected to a real family account.")
        }
        .sheet(isPresented: $showingOptions) { DemoOptionsSheet() }
    }
}
