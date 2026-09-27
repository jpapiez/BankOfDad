import Observation
import SwiftUI

@MainActor
@Observable
final class NewLoanViewModel {
    var family: FamilyDto?
    var childId: UUID?
    var title = ""
    var principal = ""
    var interestEnabled = false
    var annualRatePercent = "5"
    var frequency: Frequency = .monthly
    var installmentCount = 6
    var firstDueDate = Date()
    var lateFeesEnabled = false
    var lateFeeFlat = "5"
    var lateFeePercent = "0"
    var lateFeeGraceDays = 3
    var sendReminders = true
    var sendReceipts = true
    var preview: SchedulePreview?
    var isLoading = false
    var isSaving = false
    var error: String?
    var createdLoan: LoanDetail?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    var input: LoanTermsInput? {
        guard let childId, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return LoanTermsInput(childId: childId,
                              title: title,
                              principal: FormValues.decimal(principal),
                              interestEnabled: interestEnabled,
                              annualRate: interestEnabled ? FormValues.percentFraction(annualRatePercent) : 0,
                              frequency: frequency,
                              installmentCount: installmentCount,
                              firstDueDate: CalendarDate(firstDueDate),
                              lateFeeFlat: lateFeesEnabled ? FormValues.decimal(lateFeeFlat) : nil,
                              lateFeePercent: lateFeesEnabled ? FormValues.percentFraction(lateFeePercent) : nil,
                              lateFeeGraceDays: lateFeesEnabled ? lateFeeGraceDays : 0,
                              sendReminders: sendReminders,
                              sendReceipts: sendReceipts)
    }

    func load(family service: FamilyService) async {
        guard family == nil else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let value = try await service.family()
            family = value
            childId = value.children.first?.id
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func schedulePreview(service: LoanService) {
        previewTask?.cancel()
        guard let input else { preview = nil; return }
        previewTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            do { preview = try await service.preview(input); error = nil }
            catch { self.error = error.localizedDescription }
        }
    }

    func create(service: LoanService) async {
        guard let input else { return }
        isSaving = true; defer { isSaving = false }
        do { createdLoan = try await service.create(input); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct NewLoanView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = NewLoanViewModel()

    var body: some View {
        Form {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section("Who and what") {
                Picker("Child", selection: $viewModel.childId) {
                    ForEach(viewModel.family?.children ?? []) { child in Text(child.displayName).tag(Optional(child.id)) }
                }
                TextField("Loan title", text: $viewModel.title)
                TextField("Principal", text: $viewModel.principal)
                    .keyboardType(.decimalPad)
            }
            Section("Payment plan") {
                Toggle("Charge interest", isOn: $viewModel.interestEnabled)
                if viewModel.interestEnabled {
                    TextField("APR %", text: $viewModel.annualRatePercent).keyboardType(.decimalPad)
                }
                Picker("Frequency", selection: $viewModel.frequency) {
                    ForEach(Frequency.selectable, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("\(viewModel.installmentCount) payments", value: $viewModel.installmentCount, in: 1...520)
                DatePicker("First due date", selection: $viewModel.firstDueDate, in: Date()..., displayedComponents: .date)
            }
            Section("Late fees") {
                Toggle("Add late fee rules", isOn: $viewModel.lateFeesEnabled)
                if viewModel.lateFeesEnabled {
                    TextField("Flat amount", text: $viewModel.lateFeeFlat).keyboardType(.decimalPad)
                    TextField("Percent of missed payment", text: $viewModel.lateFeePercent).keyboardType(.decimalPad)
                    Stepper("Grace days: \(viewModel.lateFeeGraceDays)", value: $viewModel.lateFeeGraceDays, in: 0...60)
                }
            }
            Section("Notifications") {
                Toggle("Remind 15 days before each payment", isOn: $viewModel.sendReminders)
                Toggle("Send receipts when payments are recorded", isOn: $viewModel.sendReceipts)
            }
            Section("Review") {
                Button("Preview schedule") { viewModel.schedulePreview(service: environment.loanService) }
                    .disabled(viewModel.input == nil)
                if let preview = viewModel.preview {
                    LabeledContent("Payment", value: AppFormatters.money(preview.installmentAmount, currencyCode: viewModel.family?.currency ?? "USD"))
                    LabeledContent("Interest", value: AppFormatters.money(preview.totalInterest, currencyCode: viewModel.family?.currency ?? "USD"))
                    LabeledContent("Total repayable", value: AppFormatters.money(preview.totalRepayable, currencyCode: viewModel.family?.currency ?? "USD"))
                    ForEach(preview.installments.prefix(6)) { item in
                        HStack {
                            Text("#\(item.seq) • \(AppFormatters.date(item.dueDate))")
                            Spacer()
                            MoneyText(value: item.amountDue, currencyCode: viewModel.family?.currency ?? "USD")
                        }
                    }
                }
                Button(viewModel.isSaving ? "Creating…" : "Create loan") { Task { await viewModel.create(service: environment.loanService) } }
                    .disabled(viewModel.input == nil || viewModel.isSaving)
            }
        }
        .navigationTitle("New loan")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { await viewModel.load(family: environment.familyService) }
        .onChange(of: viewModel.createdLoan?.id) { _, newValue in if newValue != nil { dismiss() } }
        .onChange(of: viewModel.title) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.principal) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.interestEnabled) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.annualRatePercent) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.frequency) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.installmentCount) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.firstDueDate) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.lateFeesEnabled) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.lateFeeFlat) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.lateFeePercent) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
        .onChange(of: viewModel.lateFeeGraceDays) { _, _ in viewModel.schedulePreview(service: environment.loanService) }
    }
}
