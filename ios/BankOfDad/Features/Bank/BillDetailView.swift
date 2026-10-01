import Observation
import SwiftUI

@MainActor
@Observable
final class BillDetailViewModel {
    var detail: BillDetail?
    var isLoading = false
    var error: String?

    func load(id: UUID, service: any BillService) async {
        isLoading = true; defer { isLoading = false }
        do { detail = try await service.bill(id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func recordPayment(amount: Decimal, paidOn: CalendarDate, note: String?, service: any BillService) async {
        guard let id = detail?.id else { return }
        do { _ = try await service.recordPayment(billId: id, amount: amount, paidOn: paidOn, note: note); detail = try await service.bill(id); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func update(title: String?, amount: Decimal?, service: any BillService) async -> Bool {
        guard let id = detail?.id else { return false }
        do { detail = try await service.update(id, title: title, amount: amount); error = nil; return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func updateNotifications(service: any BillService) async {
        guard let detail else { return }
        do { self.detail = try await service.update(detail.id, sendReminders: detail.sendReminders, sendReceipts: detail.sendReceipts); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func waive(lateFeeId: UUID, service: any BillService) async {
        guard let id = detail?.id else { return }
        do { detail = try await service.waiveFee(billId: id, lateFeeId: lateFeeId); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func end(service: any BillService) async {
        guard let id = detail?.id else { return }
        do { detail = try await service.end(id); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

/// A recurring bill. Parents can record payments, change the amount, waive late fees and end it; kids see it read-only.
@MainActor
struct BillDetailView: View {
    let billId: UUID
    var isKidMode: Bool
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = BillDetailViewModel()
    @State private var paymentSheet = false
    @State private var editSheet = false
    @State private var endConfirmation = false

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.detail == nil {
                LoadingView(message: "Loading bill…")
            } else if let detail = viewModel.detail {
                List {
                    if let error = viewModel.error { ErrorBanner(message: error) }
                    header(detail)
                    Section(isKidMode ? "Your bill" : "Terms") {
                        Text(detail.termsSummary)
                            .accessibilityIdentifier("billDetail.terms")
                        LabeledContent("Amount", value: AppFormatters.money(detail.amount))
                            .accessibilityIdentifier("billDetail.amount")
                        LabeledContent("Repeats", value: detail.frequency.label)
                        if let ended = detail.endedAt { LabeledContent("Ended", value: AppFormatters.timestamp(ended)) }
                    }
                    if !isKidMode {
                        Section("Notifications") {
                            Toggle("Reminders", isOn: Binding(get: { viewModel.detail?.sendReminders ?? false }, set: { viewModel.detail?.sendReminders = $0; Task { await viewModel.updateNotifications(service: environment.billService) } }))
                                .accessibilityIdentifier("billDetail.reminders")
                            Toggle("Receipts", isOn: Binding(get: { viewModel.detail?.sendReceipts ?? false }, set: { viewModel.detail?.sendReceipts = $0; Task { await viewModel.updateNotifications(service: environment.billService) } }))
                                .accessibilityIdentifier("billDetail.receipts")
                        }
                    }
                    charges(detail)
                    lateFees(detail)
                    payments(detail)
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("billDetail.list")
            } else {
                EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "Bill unavailable", message: viewModel.error ?? "The bill could not be loaded.")
            }
        }
        .navigationTitle(viewModel.detail?.title ?? "Bill")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isKidMode, let detail = viewModel.detail {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if detail.payable > 0 {
                        Button { paymentSheet = true } label: { Label("Record Payment", systemImage: "plus.circle") }
                            .accessibilityIdentifier("billDetail.recordPayment")
                    }
                    if detail.status == .active {
                        Button { editSheet = true } label: { Label("Edit Bill", systemImage: "pencil") }
                            .accessibilityIdentifier("billDetail.edit")
                        Button(role: .destructive) { endConfirmation = true } label: { Label("End Bill", systemImage: "stop.circle") }
                            .accessibilityIdentifier("billDetail.end")
                    }
                }
            }
        }
        .sheet(isPresented: $paymentSheet) {
            if let detail = viewModel.detail {
                RecordPaymentSheet(defaultAmount: detail.balance > 0 ? detail.balance : (detail.nextAmountDue ?? detail.payable), maxAmount: detail.payable) { amount, date, note in
                    await viewModel.recordPayment(amount: amount, paidOn: date, note: note, service: environment.billService)
                }
            }
        }
        .sheet(isPresented: $editSheet) {
            if let detail = viewModel.detail {
                EditBillSheet(detail: detail) { title, amount in await viewModel.update(title: title, amount: amount, service: environment.billService) }
            }
        }
        .confirmationDialog("End this bill?", isPresented: $endConfirmation, titleVisibility: .visible) {
            Button("End bill", role: .destructive) { Task { await viewModel.end(service: environment.billService) } }
                .accessibilityIdentifier("billDetail.confirmEnd")
        } message: { Text("No new charges will be added. Anything already due is still owed.") }
        .task { await viewModel.load(id: billId, service: environment.billService) }
        .refreshable { await viewModel.load(id: billId, service: environment.billService) }
    }

    @ViewBuilder private func header(_ detail: BillDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(detail.childName).foregroundStyle(.secondary)
                MoneyText(value: detail.balance, font: .largeTitle.bold())
                    .accessibilityIdentifier("billDetail.balance")
                Text(isKidMode ? "you owe now" : "owed now").foregroundStyle(.secondary)
                HStack {
                    StatusChip(text: detail.status.label, color: detail.status == .active ? .green : .secondary)
                        .accessibilityIdentifier("billDetail.status")
                    if detail.lateCharges > 0 {
                        StatusChip(text: "\(detail.lateCharges) late", color: .red)
                            .accessibilityIdentifier("billDetail.late")
                    }
                    Spacer()
                    if let next = detail.nextDueDate, let amount = detail.nextAmountDue {
                        Text("Next: \(AppFormatters.money(amount)) on \(AppFormatters.date(next))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("billDetail.next")
                    }
                }
                Text("Paid \(AppFormatters.money(detail.amountPaid)) so far")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("billDetail.paid")
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private func charges(_ detail: BillDetail) -> some View {
        Section("Charges") {
            if detail.charges.isEmpty {
                Text("No charges").foregroundStyle(.secondary)
            } else {
                ForEach(detail.charges) { charge in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(AppFormatters.date(charge.dueDate)).font(.headline)
                            if charge.amountPaid > 0 && charge.remaining > 0 {
                                Text("\(AppFormatters.money(charge.amountPaid)) of \(AppFormatters.money(charge.amount)) paid").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            MoneyText(value: charge.remaining == 0 ? charge.amount : charge.remaining, font: .headline)
                            StatusChip(text: charge.status.label, color: color(for: charge.status))
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("billCharge.\(charge.seq)")
                }
            }
        }
    }

    @ViewBuilder private func lateFees(_ detail: BillDetail) -> some View {
        if !detail.lateFees.isEmpty || detail.lateFeeFlat != nil || detail.lateFeePercent != nil {
            Section("Late fees") {
                if detail.lateFees.isEmpty {
                    Text("No late fees").foregroundStyle(.secondary)
                        .accessibilityIdentifier("billDetail.noLateFees")
                } else {
                    ForEach(detail.lateFees) { fee in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Charge due \(AppFormatters.date(fee.chargeDueDate))")
                                Text(AppFormatters.timestamp(fee.assessedAt)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if fee.waivedAt != nil {
                                VStack(alignment: .trailing, spacing: 4) {
                                    MoneyText(value: fee.amount).strikethrough().foregroundStyle(.secondary)
                                    StatusChip(text: "Waived", color: .green)
                                }
                            } else {
                                MoneyText(value: fee.amount - fee.amountPaid)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("billLateFee.\(fee.chargeDueDate)")
                        .swipeActions {
                            if !isKidMode && fee.waivedAt == nil && fee.amountPaid < fee.amount {
                                Button("Waive") { Task { await viewModel.waive(lateFeeId: fee.id, service: environment.billService) } }.tint(.green)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func payments(_ detail: BillDetail) -> some View {
        Section("Payments") {
            if detail.payments.isEmpty {
                Text("No payments recorded yet.").foregroundStyle(.secondary)
                    .accessibilityIdentifier("billDetail.noPayments")
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
                            Text(allocationText(allocation))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("billPayment.row")
                }
            }
        }
    }

    private func allocationText(_ allocation: BillAllocation) -> String {
        let amount = AppFormatters.money(allocation.amount)
        switch allocation.target {
        case .lateFee: return "Late fee: \(amount)"
        case .charge:
            if let due = allocation.chargeDueDate { return "Charge due \(AppFormatters.date(due)): \(amount)" }
            return "Charge: \(amount)"
        default: return "\(allocation.target.rawValue): \(amount)"
        }
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
