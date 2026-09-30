import Observation
import SwiftUI

/// Which loans and bills the Owed tab shows. Paid-off and cancelled only apply to loans; ended only to bills.
enum OwedFilter: String, CaseIterable, Hashable, Sendable {
    case active, paidOff, cancelled, ended

    var label: String {
        switch self {
        case .active: return "Active"
        case .paidOff: return "Paid off loans"
        case .cancelled: return "Cancelled loans"
        case .ended: return "Ended bills"
        }
    }

    var loanStatus: LoanStatus? {
        switch self {
        case .active: return .active
        case .paidOff: return .paidOff
        case .cancelled: return .cancelled
        case .ended: return nil
        }
    }

    var showsLoans: Bool { loanStatus != nil }
    var showsBills: Bool { self == .active || self == .ended }
}

@MainActor
@Observable
final class OwedListViewModel {
    var loans: [LoanSummary] = []
    var bills: [BillSummary] = []
    var family: FamilyDto?
    var filter: OwedFilter = .active
    var childId: UUID?
    var isLoading = false
    var error: String?

    var isEmpty: Bool { loans.isEmpty && bills.isEmpty }
    var currencyCode: String { family?.currency ?? "USD" }

    func load(loans loanService: LoanService, bills billService: BillService, family familyService: FamilyService) async {
        isLoading = true; defer { isLoading = false }
        let filter = filter, childId = childId
        do {
            async let familyValue = familyService.family()
            async let loanValue = Self.fetchLoans(filter: filter, childId: childId, service: loanService)
            async let billValue = Self.fetchBills(filter: filter, childId: childId, service: billService)
            let (loadedFamily, loadedLoans, loadedBills) = try await (familyValue, loanValue, billValue)
            family = loadedFamily
            loans = loadedLoans
            bills = loadedBills
            error = nil
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private static func fetchLoans(filter: OwedFilter, childId: UUID?, service: LoanService) async throws -> [LoanSummary] {
        guard let status = filter.loanStatus else { return [] }
        return try await service.parentLoans(status: status, childId: childId)
    }

    private static func fetchBills(filter: OwedFilter, childId: UUID?, service: BillService) async throws -> [BillSummary] {
        switch filter {
        case .active:
            // An ended bill still belongs here while something on it is owed.
            return try await service.bills(childId: childId).filter { $0.status == .active || $0.balance > 0 }
        case .ended:
            return try await service.bills(status: .ended, childId: childId)
        case .paidOff, .cancelled:
            return []
        }
    }
}

/// The parent's single place for everything kids owe: loans and recurring bills across all children.
@MainActor
struct OwedListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = OwedListViewModel()
    @State private var showingNewLoan = false
    @State private var showingNewBill = false
    @State private var createdBill: BillDetail?

    var body: some View {
        List {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section {
                Picker("Show", selection: $viewModel.filter) {
                    ForEach(OwedFilter.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("owed.statusPicker")
                Picker("Child", selection: $viewModel.childId) {
                    Text("All children").tag(UUID?.none)
                    ForEach(viewModel.family?.children ?? []) { child in Text(child.displayName).tag(Optional(child.id)) }
                }
                .accessibilityIdentifier("owed.childPicker")
            }
            if viewModel.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                if viewModel.filter.showsLoans {
                    Section("Loans") {
                        if viewModel.loans.isEmpty && !viewModel.isLoading {
                            Text("No loans").foregroundStyle(.secondary)
                                .accessibilityIdentifier("owed.noLoans")
                        }
                        ForEach(viewModel.loans) { loan in
                            NavigationLink { LoanDetailView(loanId: loan.id, isKidMode: false) } label: {
                                LoanRow(loan: loan, currencyCode: viewModel.currencyCode)
                            }
                            .accessibilityIdentifier("loanRow.\(loan.id.uuidString)")
                        }
                    }
                }
                if viewModel.filter.showsBills {
                    Section("Bills") {
                        if viewModel.bills.isEmpty && !viewModel.isLoading {
                            Text("No bills").foregroundStyle(.secondary)
                                .accessibilityIdentifier("owed.noBills")
                        }
                        ForEach(viewModel.bills) { bill in
                            NavigationLink { BillDetailView(billId: bill.id, isKidMode: false) } label: {
                                BillRow(bill: bill, currencyCode: viewModel.currencyCode)
                            }
                            .accessibilityIdentifier("billRow.\(bill.id.uuidString)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Owed")
        .toolbar {
            Menu {
                Button { showingNewLoan = true } label: { Label("New Loan", systemImage: "banknote") }
                    .accessibilityIdentifier("owed.new.loan")
                Button { showingNewBill = true } label: { Label("New Bill", systemImage: "doc.text") }
                    .accessibilityIdentifier("owed.new.bill")
            } label: {
                Label("New", systemImage: "plus")
            }
            .accessibilityLabel("New loan or bill")
            .accessibilityIdentifier("owed.new")
        }
        .sheet(isPresented: $showingNewLoan, onDismiss: reload) { NavigationStack { NewLoanView() } }
        .sheet(isPresented: $showingNewBill, onDismiss: reload) {
            NewBillView { bill in createdBill = bill }
        }
        .navigationDestination(item: $createdBill) { bill in BillDetailView(billId: bill.id, isKidMode: false) }
        .task(id: OwedQuery(filter: viewModel.filter, childId: viewModel.childId)) { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder private var emptyState: some View {
        if viewModel.filter == .active {
            ContentUnavailableView {
                Label("Nothing owed", systemImage: "tray")
            } description: {
                Text("Loans are one-off amounts a child pays back in installments, like a new bike. Bills are recurring charges, like a phone plan or car insurance.")
            } actions: {
                Button { showingNewLoan = true } label: { Label("New Loan", systemImage: "banknote") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("owed.empty.newLoan")
                Button { showingNewBill = true } label: { Label("New Bill", systemImage: "doc.text") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("owed.empty.newBill")
            }
        } else {
            EmptyStateView(systemImage: "tray", title: "Nothing found", message: "Try a different filter.")
        }
    }

    private func load() async {
        await viewModel.load(loans: environment.loanService, bills: environment.billService, family: environment.familyService)
    }

    private func reload() { Task { await load() } }
}

private struct OwedQuery: Hashable {
    let filter: OwedFilter
    let childId: UUID?
}

struct LoanRow: View {
    let loan: LoanSummary
    var currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressRing(progress: progress, color: loan.status == .paidOff ? .green : Theme.bankAccent)
            VStack(alignment: .leading, spacing: 4) {
                Text(loan.title).font(.headline)
                Text(loan.childName).foregroundStyle(.secondary)
                if let due = loan.nextDueDate, let amount = loan.nextAmountDue {
                    Text("Next: \(AppFormatters.money(amount, currencyCode: currencyCode)) on \(AppFormatters.date(due))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                MoneyText(value: loan.balance, currencyCode: currencyCode, font: .headline)
                StatusChip(text: loan.status.label, color: loan.lateInstallments > 0 ? .red : .green)
            }
        }
        .padding(.vertical, 6)
    }

    private var progress: Double {
        let total = NSDecimalNumber(decimal: loan.principal).doubleValue
        guard total > 0 else { return 0 }
        return NSDecimalNumber(decimal: loan.amountPaid).doubleValue / total
    }
}

struct BillRow: View {
    let bill: BillSummary
    var currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title2)
                .foregroundStyle(Theme.bankAccent)
                .frame(width: 58, height: 58)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(bill.title).font(.headline)
                Text(bill.childName).foregroundStyle(.secondary)
                Text("\(AppFormatters.money(bill.amount, currencyCode: currencyCode)) \(bill.frequency.label.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let due = bill.nextDueDate, let amount = bill.nextAmountDue {
                    Text("Next: \(AppFormatters.money(amount, currencyCode: currencyCode)) on \(AppFormatters.date(due))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                MoneyText(value: bill.balance, currencyCode: currencyCode, font: .headline)
                StatusChip(text: chipText, color: chipColor)
            }
        }
        .padding(.vertical, 6)
    }

    private var chipText: String { bill.lateCharges > 0 ? "\(bill.lateCharges) late" : bill.status.label }
    private var chipColor: Color {
        if bill.lateCharges > 0 { return .red }
        return bill.status == .active ? .green : .gray
    }
}
