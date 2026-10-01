import SwiftUI

/// Demo controls: switch between the parent and each kid, reset the sample data, or leave the demo.
struct DemoOptionsSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var isWorking = false
    @State private var resetConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await switchTo(role: .parent, childId: nil) }
                    } label: {
                        row(title: "Parent", subtitle: "See the family dashboard, loans, and bills.", systemImage: "person.2.badge.gearshape.fill", isCurrent: environment.demo?.role == .parent)
                    }
                    .accessibilityIdentifier("demo.switch.parent")

                    ForEach(environment.demo?.children ?? [], id: \.id) { child in
                        Button {
                            Task { await switchTo(role: .child, childId: child.id) }
                        } label: {
                            row(title: child.displayName, subtitle: "See the demo from this kid's phone.", systemImage: "sparkles", isCurrent: environment.demo?.role == .child && environment.demo?.activeChild?.id == child.id)
                        }
                        .accessibilityIdentifier("demo.switch.child.\(child.displayName)")
                    }
                } header: {
                    Text("Explore as")
                } footer: {
                    Text("Everything in the demo is sample data stored on this device. Nothing is sent to the Bank of Dad servers.")
                }

                Section {
                    Button {
                        resetConfirmation = true
                    } label: {
                        Label("Reset demo data", systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityIdentifier("demo.reset")

                    Button(role: .destructive) {
                        Task {
                            await environment.exitDemo()
                            dismiss()
                        }
                    } label: {
                        Label("Exit demo", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .accessibilityIdentifier("demo.exit")
                }
            }
            .disabled(isWorking)
            .navigationTitle("Demo options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("demo.options.done")
                }
            }
            .confirmationDialog("Reset the demo back to its starting point?", isPresented: $resetConfirmation, titleVisibility: .visible) {
                Button("Reset demo data", role: .destructive) {
                    Task {
                        isWorking = true
                        await environment.resetDemoData()
                        isWorking = false
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Any changes you made while exploring will be discarded.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func switchTo(role: Role, childId: UUID?) async {
        isWorking = true
        await environment.switchDemoRole(to: role, childId: childId)
        isWorking = false
        dismiss()
    }

    private func row(title: String, subtitle: String, systemImage: String, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(Theme.bankAccent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
