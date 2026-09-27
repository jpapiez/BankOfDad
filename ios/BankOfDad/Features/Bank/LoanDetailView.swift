import Observation
import SwiftUI

@MainActor
@Observable
final class LoanDetailViewModel {
    var detail: LoanDetail?
    var isLoading = false
    var error: String?
    var isKidMode = false

    func load(id: UUID, service: LoanService, kidMode: Bool) async {
        isKidMode = kidMode
        isLoading = true; defer { isLoading = false }
        do {
            if kidMode { detail = try await service.myLoan(id) } else { detail = try await service.loan(id) }
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }

    func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate, service: LoanService) async {
        do { detail = try await service.updateInstallment(loanId: loanId, installmentId: installmentId, dueDate: dueDate); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func recordPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?, service: LoanService) async {
        do { _ = try await service.recordPayment(loanId: loanId, amount: amount, paidOn: paidOn, note: note); detail = try await service.loan(loanId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func waive(lateFeeId: UUID, service: LoanService) async {
        guard let loanId = detail?.id else { return }
        do { detail = try await service.waiveFee(loanId: loanId, lateFeeId: lateFeeId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func cancel(service: LoanService) async {
        guard let id = detail?.id else { return }
        do { detail = try await service.cancel(id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func updateNotifications(service: LoanService) async {
        guard let detail else { return }
        do { self.detail = try await service.updateLoan(detail.id, sendReminders: detail.sendReminders, sendReceipts: detail.sendReceipts); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct LoanDetailView: View {
    let loanId: UUID
    var isKidMode: Bool
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = LoanDetailViewModel()
    @State private var paymentSheet = false
    @State private var editInstallment: Installment?
    @State private var cancelConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                LoadingView(message: "Loading loan…")
            } else if let detail = viewModel.detail {
                List {
                    header(detail)
                    Section(isKidMode ? "Your plan" : "Terms") {
                        Text(detail.termsSummary)
                        LabeledContent("Frequency", value: detail.frequency.label)
                        LabeledContent("Payments", value: "\(detail.installmentCount)")
                        if detail.interestEnabled { LabeledContent("APR", value: AppFormatters.percent(detail.annualRate)) }
                    }
                    if !isKidMode {
                        Section("Notifications") {
                            Toggle("Reminders", isOn: Binding(get: { viewModel.detail?.sendReminders ?? false }, set: { viewModel.detail?.sendReminders = $0; Task { await viewModel.updateNotifications(service: environment.loanService) } }))
                            Toggle("Receipts", isOn: Binding(get: { viewModel.detail?.sendReceipts ?? false }, set: { viewModel.detail?.sendReceipts = $0; Task { await viewModel.updateNotifications(service: environment.loanService) } }))
                        }
                    }
                    schedule(detail)
                    lateFees(detail)
                    payments(detail)
                }
                .listStyle(.insetGrouped)
            } else {
                EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "Loan unavailable", message: viewModel.error ?? "The loan could not be loaded.")
            }
        }
        .navigationTitle(viewModel.detail?.title ?? "Loan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isKidMode, viewModel.detail?.status == .active {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { paymentSheet = true } label: { Label("Record Payment", systemImage: "plus.circle") }
                    Button(role: .destructive) { cancelConfirmation = true } label: { Label("Cancel Loan", systemImage: "xmark.circle") }
                }
            }
        }
        .sheet(isPresented: $paymentSheet) {
            if let detail = viewModel.detail { RecordPaymentSheet(detail: detail) { amount, date, note in await viewModel.recordPayment(loanId: detail.id, amount: amount, paidOn: date, note: note, service: environment.loanService) } }
        }
        .sheet(item: $editInstallment) { installment in
            EditDueDateSheet(installment: installment) { date in
                await viewModel.updateInstallment(loanId: loanId, installmentId: installment.id, dueDate: date, service: environment.loanService)
            }
        }
        .confirmationDialog("Cancel this loan?", isPresented: $cancelConfirmation, titleVisibility: .visible) {
            Button("Cancel loan", role: .destructive) { Task { await viewModel.cancel(service: environment.loanService) } }
        } message: { Text("Cancelled loans stop new reminders and payments.") }
        .task { await viewModel.load(id: loanId, service: environment.loanService, kidMode: isKidMode) }
        .refreshable { await viewModel.load(id: loanId, service: environment.loanService, kidMode: isKidMode) }
    }

    @ViewBuilder private func header(_ detail: LoanDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(detail.childName).foregroundStyle(.secondary)
                        MoneyText(value: detail.balance, font: .largeTitle.bold())
                        Text("balance remaining").foregroundStyle(.secondary)
                    }
                    Spacer()
                    ProgressRing(progress: progress(detail), color: isKidMode ? Theme.kidAccent : Theme.bankAccent)
                }
                HStack {
                    StatusChip(text: detail.status.label, color: detail.status == .active ? .green : .secondary)
                    if detail.lateInstallments > 0 { StatusChip(text: "\(detail.lateInstallments) late", color: .red) }
                    Spacer()
                    Text(isKidMode ? "You've paid back \(Int(progress(detail) * 100))%! 🎉" : "Paid \(AppFormatters.money(detail.amountPaid))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private func schedule(_ detail: LoanDetail) -> some View {
        Section("Schedule") {
            ForEach(detail.installments) { installment in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Payment #\(installment.seq)").font(.headline)
                        Text(AppFormatters.date(installment.dueDate)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        MoneyText(value: installment.remaining == 0 ? installment.amountDue : installment.remaining, font: .headline)
                        StatusChip(text: installment.status.label, color: color(for: installment.status))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if !isKidMode && installment.status != .paid { editInstallment = installment } }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !isKidMode && installment.status != .paid {
                        Button("Edit due date") { editInstallment = installment }.tint(.blue)
                    }
                }
            }
        }
    }

    @ViewBuilder private func lateFees(_ detail: LoanDetail) -> some View {
        Section("Late fees") {
            if detail.lateFees.isEmpty {
                Text("No late fees").foregroundStyle(.secondary)
            } else {
                ForEach(detail.lateFees) { fee in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Installment #\(fee.installmentSeq)")
                            Text(AppFormatters.timestamp(fee.assessedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        MoneyText(value: fee.amount - fee.amountPaid)
                    }
                    .swipeActions {
                        if !isKidMode && fee.waivedAt == nil {
                            Button("Waive") { Task { await viewModel.waive(lateFeeId: fee.id, service: environment.loanService) } }.tint(.green)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func payments(_ detail: LoanDetail) -> some View {
        Section("Payments") {
            if detail.payments.isEmpty {
                Text(isKidMode ? "No payments yet — you've got this." : "No payments recorded yet.").foregroundStyle(.secondary)
            } else {
                ForEach(detail.payments) { payment in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            MoneyText(value: payment.amount, font: .headline)
                            Spacer()
                            Text(AppFormatters.date(payment.paidOn)).foregroundStyle(.secondary)
                        }
                        if let note = payment.note, !note.isEmpty { Text(note).font(.callout) }
                        ForEach(payment.allocations) { allocation in
                            Text("\(allocation.target.rawValue): \(AppFormatters.money(allocation.amount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func progress(_ detail: LoanDetail) -> Double {
        let total = NSDecimalNumber(decimal: detail.totalRepayable).doubleValue
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: detail.amountPaid).doubleValue / total
    }

    private func color(for status: InstallmentStatus) -> Color {
        switch status {
        case .paid: return .green
        case .late: return .red
        case .due: return .orange
        case .upcoming, .unknown: return .secondary
        }
    }
}

struct RecordPaymentSheet: View {
    let detail: LoanDetail
    let onSave: (Decimal, CalendarDate, String?) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var paidOn = Date()
    @State private var note = ""

    init(detail: LoanDetail, onSave: @escaping (Decimal, CalendarDate, String?) async -> Void) {
        self.detail = detail
        self.onSave = onSave
        _amount = State(initialValue: NSDecimalNumber(decimal: detail.nextAmountDue ?? detail.balance).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                DatePicker("Paid on", selection: $paidOn, displayedComponents: .date)
                TextField("Note", text: $note, axis: .vertical)
                if FormValues.decimal(amount) > detail.balance { ErrorBanner(message: "Payment cannot exceed the remaining balance.") }
            }
            .navigationTitle("Record payment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await onSave(FormValues.decimal(amount), CalendarDate(paidOn), note); dismiss() } }
                        .disabled(FormValues.decimal(amount) <= 0 || FormValues.decimal(amount) > detail.balance)
                }
            }
        }
    }
}

struct EditDueDateSheet: View {
    let installment: Installment
    let onSave: (CalendarDate) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(installment: Installment, onSave: @escaping (CalendarDate) async -> Void) {
        self.installment = installment
        self.onSave = onSave
        _date = State(initialValue: installment.dueDate.date())
    }

    var body: some View {
        NavigationStack {
            Form { DatePicker("Due date", selection: $date, displayedComponents: .date) }
                .navigationTitle("Edit due date")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await onSave(CalendarDate(date)); dismiss() } } }
                }
        }
    }
}
