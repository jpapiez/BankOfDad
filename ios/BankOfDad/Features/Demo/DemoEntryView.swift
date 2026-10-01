import SwiftUI

/// Entry point for "Explore Demo": pick which side of the family to explore first.
struct DemoEntryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isStarting = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.bankAccent)
                    .accessibilityHidden(true)
                Text("Explore the demo")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Meet the Parkers: two kids, a few loans, some recurring bills, and a payment that slipped. Everything runs on this device with sample data — no account needed and nothing is sent anywhere.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(spacing: 14) {
                Button {
                    start(role: .parent)
                } label: {
                    Label("Explore as a parent", systemImage: "person.2.badge.gearshape.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.bankAccent)
                .accessibilityIdentifier("demo.start.parent")

                Button {
                    start(role: .child)
                } label: {
                    Label("Explore as a kid", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(Theme.kidAccent)
                .accessibilityIdentifier("demo.start.kid")

                Text("You can switch roles, reset the data, or leave the demo at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .disabled(isStarting)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Demo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func start(role: Role) {
        guard !isStarting else { return }
        isStarting = true
        Task {
            await environment.enterDemo(role: role)
            isStarting = false
        }
    }
}
