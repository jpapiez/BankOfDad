import SwiftUI

/// Rename a child and change their avatar color.
@MainActor
struct EditChildSheet: View {
    let child: ChildDto
    let onSaved: @MainActor (ChildDto) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var color: String?
    @State private var isSaving = false
    @State private var error: String?

    init(child: ChildDto, onSaved: @escaping @MainActor (ChildDto) -> Void) {
        self.child = child
        self.onSaved = onSaved
        _name = State(initialValue: child.displayName)
        _color = State(initialValue: child.avatarColor)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if let error { ErrorBanner(message: error) }
                Section("Name") {
                    TextField("Child name", text: $name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("editChild.name")
                }
                AvatarColorPicker(name: trimmedName, selection: $color)
            }
            .navigationTitle("Edit child")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("editChild.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(trimmedName.isEmpty || isSaving)
                        .accessibilityIdentifier("editChild.save")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() async {
        isSaving = true; defer { isSaving = false }
        do {
            // Only send the color when it changed, so a legacy value is never re-validated.
            let newColor = color == child.avatarColor ? nil : color
            let updated = try await environment.familyService.updateChild(child.id, displayName: trimmedName, avatarColor: newColor)
            onSaved(updated)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
