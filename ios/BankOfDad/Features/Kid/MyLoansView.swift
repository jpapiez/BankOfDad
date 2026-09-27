import Observation
import SwiftUI

@MainActor
@Observable
final class MyLoansViewModel {
    var loans: [LoanSummary] = []
    var isLoading = false
    var error: String?

    func load(service: LoanService) async {
        isLoading = true; defer { isLoading = false }
        do { loans = try await service.myLoans(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct MyLoansView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = MyLoansViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error { ErrorBanner(message: error) }
                if viewModel.loans.isEmpty && !viewModel.isLoading {
                    EmptyStateView(systemImage: "party.popper", title: "No loans right now", message: "When the Bank adds a loan, it will show up here.")
                        .padding(.top, 80)
                } else {
                    ForEach(viewModel.loans) { loan in
                        NavigationLink { KidLoanDetailView(loanId: loan.id) } label: {
                            KidLoanCard(loan: loan)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My loans")
        .task { await viewModel.load(service: environment.loanService) }
        .refreshable { await viewModel.load(service: environment.loanService) }
    }
}

struct KidLoanCard: View {
    let loan: LoanSummary

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                ProgressRing(progress: progress, color: Theme.kidAccent)
                VStack(alignment: .leading, spacing: 6) {
                    Text(loan.title).font(.title3.bold())
                    Text("You've paid back \(Int(progress * 100))%! 🎉")
                        .foregroundStyle(.secondary)
                    if let next = loan.nextDueDate, let amount = loan.nextAmountDue {
                        Text("Next: \(AppFormatters.money(amount)) on \(AppFormatters.date(next))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All caught up!").foregroundStyle(.green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Balance").font(.caption).foregroundStyle(.secondary)
                    MoneyText(value: loan.balance, font: .headline)
                }
            }
        }
    }

    private var progress: Double {
        let principal = NSDecimalNumber(decimal: loan.principal).doubleValue
        guard principal > 0 else { return 0 }
        return NSDecimalNumber(decimal: loan.amountPaid).doubleValue / principal
    }
}
