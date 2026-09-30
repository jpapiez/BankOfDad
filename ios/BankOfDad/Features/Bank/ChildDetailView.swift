import Observation
import SwiftUI

@MainActor
@Observable
final class ChildDetailViewModel {
    var loans: [LoanSummary] = []
    var bills: [BillSummary] = []
    var isLoading = false
    var error: String?

    // Cancelled loans keep a balance but aren't owed (matches the dashboard's total).
    var totalOwed: Decimal { loans.filter { $0.status == .active }.reduce(0) { $0 + $1.balance } + bills.reduce(0) { $0 + $1.balance } }
    var activeBills: [BillSummary] { bills.filter { $0.status == .active } }
    var endedBills: [BillSummary] { bills.filter { $0.status != .active } }

    func load(childId: UUID, loanService: LoanService, billService: BillService) async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loans = loanService.parentLoans(childId: childId)
            async let bills = billService.bills(childId: childId)
            (self.loans, self.bills) = try await (loans, bills)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// One child's loans and recurring bills, with the total they owe now.
@MainActor
struct ChildDetailView: View {
    @State private var child: ChildDto
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = ChildDetailViewModel()
    @State private var addingBill = false
    @State private var createdBill: BillDetail?
    @State private var editingChild = false

    init(child: ChildDto) { _child = State(initialValue: child) }

    var body: some View {
        List {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section {
                HStack(spacing: 16) {
                    AvatarView(name: child.displayName, colorHex: child.avatarColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Owes now").foregroundStyle(.secondary)
                        MoneyText(value: viewModel.totalOwed, font: .title.bold())
                            .accessibilityIdentifier("childDetail.totalOwed")
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                if viewModel.activeBills.isEmpty && !viewModel.isLoading {
                    Text("No recurring bills").foregroundStyle(.secondary)
                        .accessibilityIdentifier("childDetail.noBills")
                }
                ForEach(viewModel.activeBills) { bill in billRow(bill) }
                Button { addingBill = true } label: { Label("Add bill", systemImage: "plus") }
                    .accessibilityIdentifier("childDetail.addBill")
            } header: { Text("Bills") } footer: { Text("Recurring charges like a phone plan, car insurance or rent.") }
            if !viewModel.endedBills.isEmpty {
                Section("Ended bills") {
                    ForEach(viewModel.endedBills) { bill in billRow(bill) }
                }
            }
            Section("Loans") {
                if viewModel.loans.isEmpty && !viewModel.isLoading {
                    Text("No loans").foregroundStyle(.secondary)
                }
                ForEach(viewModel.loans) { loan in
                    NavigationLink { LoanDetailView(loanId: loan.id, isKidMode: false) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loan.title).font(.headline)
                                Text(loan.status.label).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            MoneyText(value: loan.balance)
                        }
                    }
                    .accessibilityIdentifier("childDetail.loan.\(loan.title)")
                }
            }
        }
        .navigationTitle(child.displayName)
        .navigationDestination(item: $createdBill) { bill in BillDetailView(billId: bill.id, isKidMode: false) }
        .toolbar { Button { addingBill = true } label: { Label("Add bill", systemImage: "plus") }.accessibilityIdentifier("childDetail.addBillToolbar") }
        .sheet(isPresented: $addingBill, onDismiss: reload) {
            NewBillView(childId: child.id, childName: child.displayName) { bill in createdBill = bill }
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit") { editingChild = true }.accessibilityIdentifier("childDetail.edit") } }
        .sheet(isPresented: $editingChild) { EditChildSheet(child: child) { child = $0 } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func billRow(_ bill: BillSummary) -> some View {
        NavigationLink { BillDetailView(billId: bill.id, isKidMode: false) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.title).font(.headline)
                    Text("\(AppFormatters.money(bill.amount)) \(bill.frequency.label.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    MoneyText(value: bill.balance)
                    if bill.lateCharges > 0 { StatusChip(text: "\(bill.lateCharges) late", color: .red) }
                }
            }
        }
        .accessibilityIdentifier("childDetail.bill.\(bill.title)")
    }

    private func load() async {
        await viewModel.load(childId: child.id, loanService: environment.loanService, billService: environment.billService)
    }

    private func reload() { Task { await load() } }
}
