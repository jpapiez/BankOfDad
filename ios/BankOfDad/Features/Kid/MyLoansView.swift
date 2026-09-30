import Observation
import SwiftUI

@MainActor
@Observable
final class MyLoansViewModel {
    var loans: [LoanSummary] = []
    var bills: [BillSummary] = []
    var isLoading = false
    var error: String?

    func load(service: LoanService, billService: BillService) async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loans = service.myLoans()
            async let bills = billService.bills()
            let (loadedLoans, loadedBills) = try await (loans, bills)
            self.loans = loadedLoans
            // Ended bills only matter to the kid while something is still owed on them.
            self.bills = loadedBills.filter { $0.status == .active || $0.balance > 0 }
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct MyLoansView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = MyLoansViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error { ErrorBanner(message: error) }
                if viewModel.loans.isEmpty && viewModel.bills.isEmpty && !viewModel.isLoading {
                    EmptyStateView(systemImage: "party.popper", title: "No loans right now", message: "When the Bank adds a loan, it will show up here.")
                        .padding(.top, 80)
                } else {
                    if !viewModel.bills.isEmpty {
                        Text("My bills")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("kidBills.header")
                        ForEach(viewModel.bills) { bill in
                            NavigationLink { BillDetailView(billId: bill.id, isKidMode: true) } label: {
                                KidBillCard(bill: bill)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("kidBill.\(bill.id.uuidString)")
                        }
                        if !viewModel.loans.isEmpty {
                            Text("My loans")
                                .font(.title2.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    ForEach(viewModel.loans) { loan in
                        NavigationLink { KidLoanDetailView(loanId: loan.id) } label: {
                            KidLoanCard(loan: loan)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("kidLoan.\(loan.id.uuidString)")
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("My loans")
        .task { await viewModel.load(service: environment.loanService, billService: environment.billService) }
        .refreshable { await viewModel.load(service: environment.loanService, billService: environment.billService) }
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

struct KidBillCard: View {
    let bill: BillSummary

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "doc.text.fill")
                    .font(.title)
                    .foregroundStyle(Theme.kidAccent)
                    .frame(width: 58, height: 58)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(bill.title).font(.title3.bold())
                    Text("\(AppFormatters.money(bill.amount)) \(bill.frequency.label.lowercased())")
                        .foregroundStyle(.secondary)
                    if bill.balance > 0 {
                        Text(bill.lateCharges > 0 ? "\(bill.lateCharges) late — time to catch up" : "Due now")
                            .font(.callout)
                            .foregroundStyle(bill.lateCharges > 0 ? .red : .orange)
                    } else if let next = bill.nextDueDate, let amount = bill.nextAmountDue {
                        Text("Next: \(AppFormatters.money(amount)) on \(AppFormatters.date(next))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All caught up!").foregroundStyle(.green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Owe now").font(.caption).foregroundStyle(.secondary)
                    MoneyText(value: bill.balance, font: .headline)
                }
            }
        }
    }
}
