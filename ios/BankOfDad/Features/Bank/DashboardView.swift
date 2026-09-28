import Observation
import SwiftUI

@MainActor
@Observable
final class DashboardViewModel {
    var dashboard: Dashboard?
    var isLoading = false
    var error: String?

    func load(service: LoanService) async {
        isLoading = true; defer { isLoading = false }
        do { dashboard = try await service.dashboard(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct DashboardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let error = viewModel.error { ErrorBanner(message: error) }
                if let dashboard = viewModel.dashboard {
                    Card {
                        Text("Outstanding")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        MoneyText(value: dashboard.totalOutstanding, font: .largeTitle.bold())
                            .accessibilityIdentifier("dashboard.outstanding")
                        HStack {
                            Label("\(dashboard.activeLoans) active", systemImage: "checklist")
                                .accessibilityIdentifier("dashboard.active")
                            Spacer()
                            Label("\(dashboard.lateInstallments) late", systemImage: "clock.badge.exclamationmark")
                                .accessibilityIdentifier("dashboard.late")
                        }
                        .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Coming up")
                            .font(.title2.bold())
                        if dashboard.upcoming.isEmpty {
                            EmptyStateView(systemImage: "calendar.badge.checkmark", title: "Nothing due soon", message: "Upcoming and late installments will appear here.")
                        } else {
                            ForEach(dashboard.upcoming) { item in
                                NavigationLink { LoanDetailView(loanId: item.loanId, isKidMode: false) } label: {
                                    Card {
                                        HStack(alignment: .firstTextBaseline) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.loanTitle).font(.headline)
                                                Text("\(item.childName) • \(AppFormatters.date(item.dueDate))").foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            MoneyText(value: item.amountDue, font: .headline)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("dashboard.upcoming.\(item.loanId.uuidString)")
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    LoadingView(message: "Loading dashboard…").frame(height: 260)
                }
            }
            .padding()
        }
        .navigationTitle("Bank dashboard")
        .background(Color(.systemGroupedBackground))
        .task { await viewModel.load(service: environment.loanService) }
        .refreshable { await viewModel.load(service: environment.loanService) }
    }
}
