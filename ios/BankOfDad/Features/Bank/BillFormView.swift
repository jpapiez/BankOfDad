import Observation
import SwiftUI

@MainActor
@Observable
final class NewBillViewModel {
    let childId: UUID
    var title = ""
    var amount = ""
    var frequency: Frequency = .monthly
    var firstDueDate = Date()
    var lateFeesEnabled = false
    var lateFeeFlat = "5"
    var lateFeePercent = "0"
    var lateFeeGraceDays = 3
    var sendReminders = true
    var sendReceipts = true
    var isSaving = false
    var error: String?
    var createdBill: BillDetail?

    init(childId: UUID) { self.childId = childId }

    var input: BillInput? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = FormValues.decimal(amount)
        guard !trimmed.isEmpty, value > 0 else { return nil }
        return BillInput(childId: childId,
                         title: trimmed,
                         amount: value,
                         frequency: frequency,
                         firstDueDate: CalendarDate(firstDueDate),
                         lateFeeFlat: lateFeesEnabled ? FormValues.decimal(lateFeeFlat) : nil,
                         lateFeePercent: lateFeesEnabled ? FormValues.percentFraction(lateFeePercent) : nil,
                         lateFeeGraceDays: lateFeesEnabled ? lateFeeGraceDays : 0,
                         sendReminders: sendReminders,
                         sendReceipts: sendReceipts)
    }

    func create(service: BillService) async {
        guard let input else { return }
        isSaving = true; defer { isSaving = false }
        do { createdBill = try await service.create(input); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// Creates a recurring bill (cell phone, car insurance, rent…) for one child.
@MainActor
struct NewBillView: View {
    let childName: String
    let onCreated: @MainActor (BillDetail) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: NewBillViewModel

    init(childId: UUID, childName: String, onCreated: @escaping @MainActor (BillDetail) -> Void) {
        self.childName = childName
        self.onCreated = onCreated
        _viewModel = State(initialValue: NewBillViewModel(childId: childId))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = viewModel.error { ErrorBanner(message: error) }
                Section {
                    TextField("Bill name (e.g. Cell phone)", text: $viewModel.title)
                        .accessibilityIdentifier("newBill.title")
                    TextField("Amount each time", text: $viewModel.amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("newBill.amount")
                } header: { Text("What \(childName) pays") }
                Section {
                    Picker("Repeats", selection: $viewModel.frequency) {
                        ForEach(Frequency.billSelectable, id: \.self) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("newBill.frequency")
                    DatePicker("First due date", selection: $viewModel.firstDueDate, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        .accessibilityIdentifier("newBill.firstDueDate")
                } header: { Text("Schedule") } footer: { Text("The bill repeats until you end it.") }
                Section("Late fees") {
                    Toggle("Add late fee rules", isOn: $viewModel.lateFeesEnabled)
                        .accessibilityIdentifier("newBill.lateFees")
                    if viewModel.lateFeesEnabled {
                        TextField("Flat amount", text: $viewModel.lateFeeFlat).keyboardType(.decimalPad)
                            .accessibilityIdentifier("newBill.lateFeeFlat")
                        TextField("Percent of missed payment", text: $viewModel.lateFeePercent).keyboardType(.decimalPad)
                            .accessibilityIdentifier("newBill.lateFeePercent")
                        Stepper("Grace days: \(viewModel.lateFeeGraceDays)", value: $viewModel.lateFeeGraceDays, in: 0...60)
                            .accessibilityIdentifier("newBill.graceDays")
                    }
                }
                Section("Notifications") {
                    Toggle("Remind 15 days before each charge", isOn: $viewModel.sendReminders)
                        .accessibilityIdentifier("newBill.reminders")
                    Toggle("Send receipts when payments are recorded", isOn: $viewModel.sendReceipts)
                        .accessibilityIdentifier("newBill.receipts")
                }
            }
            .navigationTitle("New bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("newBill.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "Saving…" : "Create") { Task { await viewModel.create(service: environment.billService) } }
                        .disabled(viewModel.input == nil || viewModel.isSaving)
                        .accessibilityIdentifier("newBill.create")
                }
            }
            .onChange(of: viewModel.createdBill?.id) { _, newValue in
                if newValue != nil, let bill = viewModel.createdBill { onCreated(bill); dismiss() }
            }
        }
    }
}

/// Edits a bill's name and amount. A new amount only applies to charges that aren't due yet.
@MainActor
struct EditBillSheet: View {
    let detail: BillDetail
    let onSave: @MainActor (String?, Decimal?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var amount: String
    @State private var isSaving = false

    init(detail: BillDetail, onSave: @escaping @MainActor (String?, Decimal?) async -> Bool) {
        self.detail = detail
        self.onSave = onSave
        _title = State(initialValue: detail.title)
        _amount = State(initialValue: NSDecimalNumber(decimal: detail.amount).stringValue)
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var newAmount: Decimal { FormValues.decimal(amount) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Bill name", text: $title)
                        .accessibilityIdentifier("editBill.title")
                    TextField("Amount each time", text: $amount)
                        .keyboardType(.decimalPad)
                        .disabled(detail.status != .active)
                        .accessibilityIdentifier("editBill.amount")
                } footer: {
                    Text("A new amount applies to future charges only. Charges that are already due keep their amount.")
                }
            }
            .navigationTitle("Edit bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("editBill.cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            let saved = await onSave(trimmedTitle == detail.title ? nil : trimmedTitle, newAmount == detail.amount ? nil : newAmount)
                            isSaving = false
                            if saved { dismiss() }
                        }
                    }
                    .disabled(trimmedTitle.isEmpty || newAmount <= 0 || isSaving)
                    .accessibilityIdentifier("editBill.save")
                }
            }
        }
    }
}
