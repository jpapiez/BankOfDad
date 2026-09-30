import Observation
import SwiftUI

@MainActor
@Observable
final class InboxViewModel {
    var notifications: [AppNotification] = []
    var error: String?
    var isLoading = false

    func load(service: NotificationService) async {
        isLoading = true; defer { isLoading = false }
        do { notifications = try await service.notifications(); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func markRead(_ notification: AppNotification, service: NotificationService) async {
        guard notification.readAt == nil else { return }
        do { try await service.markRead(notification.id); if let index = notifications.firstIndex(where: { $0.id == notification.id }) { notifications[index].readAt = Date() } }
        catch { self.error = error.localizedDescription }
    }

    func markAll(service: NotificationService) async {
        do { try await service.markAllRead(); notifications = notifications.map { var copy = $0; copy.readAt = copy.readAt ?? Date(); return copy } }
        catch { self.error = error.localizedDescription }
    }
}

@MainActor
struct InboxView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel = InboxViewModel()

    var body: some View {
        List {
            if let error = viewModel.error { ErrorBanner(message: error) }
            if viewModel.notifications.isEmpty && !viewModel.isLoading {
                EmptyStateView(systemImage: "bell.slash", title: "No messages", message: "Receipts, reminders, and late-fee notes will arrive here.")
            } else {
                ForEach(viewModel.notifications) { notification in
                    notificationRow(notification)
                }
            }
        }
        .navigationTitle("Inbox")
        .toolbar { Button("Mark all read") { Task { await viewModel.markAll(service: environment.notificationService) } }.accessibilityIdentifier("inbox.markAllRead") }
        .task { await viewModel.load(service: environment.notificationService) }
        .refreshable { await viewModel.load(service: environment.notificationService) }
    }

    @ViewBuilder private func notificationRow(_ notification: AppNotification) -> some View {
        if let loanId = notification.loanId {
            NavigationLink { KidLoanDetailView(loanId: loanId) } label: { rowContent(notification) }
                .task { await viewModel.markRead(notification, service: environment.notificationService) }
        } else if let billId = notification.billId {
            NavigationLink { BillDetailView(billId: billId, isKidMode: true) } label: { rowContent(notification) }
                .task { await viewModel.markRead(notification, service: environment.notificationService) }
        } else {
            rowContent(notification)
                .task { await viewModel.markRead(notification, service: environment.notificationService) }
        }
    }

    private func rowContent(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(for: notification.type))
                .foregroundStyle(notification.readAt == nil ? Theme.kidAccent : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(notification.readAt == nil ? .headline : .body)
                Text(notification.body).foregroundStyle(.secondary)
                Text(AppFormatters.timestamp(notification.createdAt)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(notification.readAt == nil ? "Unread" : "Read")
        .accessibilityIdentifier("inbox.\(notification.type.rawValue)")
    }

    private func icon(for type: NotificationType) -> String {
        switch type {
        case .reminder: return "calendar.badge.clock"
        case .receipt: return "checkmark.seal.fill"
        case .loanCreated: return "sparkles"
        case .lateFee: return "exclamationmark.triangle.fill"
        case .billCreated: return "doc.text.fill"
        case .unknown: return "bell.fill"
        }
    }
}
