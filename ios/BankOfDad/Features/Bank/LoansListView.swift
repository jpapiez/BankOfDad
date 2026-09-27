import Observation
import SwiftUI

@MainActor
@Observable
final class LoansListViewModel {
    var loans: [LoanSummary] = []
    var family: FamilyDto?
    var status: LoanStatus = .active
    var childId: UUID?
    var isLoading = false
    var error: String?

    func load(loans loanService: LoanService, family familyService: FamilyService) async {
        isLoading = true; defer { isLoading = false }
        do {
            async let familyValue = familyService.family()
            async let loanValue = loanService.parentLoans(status: status == .unknown ? nil : status, childId: childId)
            family = try await familyValue
            loans = try await loanValue
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct LoansListView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = LoansListViewModel()
    @State private var showingNewLoan = false

    var body: some View {
        List {
            if let error = viewModel.error { ErrorBanner(message: error) }
            Section {
                Picker("Status", selection: $viewModel.status) {
                    Text("Active").tag(LoanStatus.active)
                    Text("Paid off").tag(LoanStatus.paidOff)
                    Text("Cancelled").tag(LoanStatus.cancelled)
                }
                Picker("Child", selection: $viewModel.childId) {
                    Text("All children").tag(UUID?.none)
                    ForEach(viewModel.family?.children ?? []) { child in Text(child.displayName).tag(Optional(child.id)) }
                }
            }
            if viewModel.loans.isEmpty && !viewModel.isLoading {
                EmptyStateView(systemImage: "tray", title: "No loans found", message: "Create a new loan or adjust the filters.")
            } else {
                ForEach(viewModel.loans) { loan in
                    NavigationLink { LoanDetailView(loanId: loan.id, isKidMode: false) } label: {
                        LoanRow(loan: loan, currencyCode: viewModel.family?.currency ?? "USD")
                    }
                }
            }
        }
        .navigationTitle("Loans")
        .toolbar { Button { showingNewLoan = true } label: { Label("New Loan", systemImage: "plus") } }
        .sheet(isPresented: $showingNewLoan) { NavigationStack { NewLoanView() } }
        .task(id: viewModel.status) { await viewModel.load(loans: environment.loanService, family: environment.familyService) }
        .task(id: viewModel.childId) { await viewModel.load(loans: environment.loanService, family: environment.familyService) }
        .refreshable { await viewModel.load(loans: environment.loanService, family: environment.familyService) }
    }
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
