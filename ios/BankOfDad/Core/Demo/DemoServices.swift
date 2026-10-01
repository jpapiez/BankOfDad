import Foundation

/// Demo implementations of the app's service protocols. They never touch the network: every call is
/// answered by the local `DemoStore`.

struct DemoFamilyService: FamilyService {
    let store: DemoStore

    func family() async throws -> FamilyDto { await store.family() }
    func updateFamily(name: String?, timeZone: String?) async throws -> FamilyDto { await store.updateFamily(name: name, timeZone: timeZone) }
    func addChild(displayName: String, avatarColor: String?) async throws -> ChildDto { await store.addChild(displayName: displayName, avatarColor: avatarColor) }
    func updateChild(_ childId: UUID, displayName: String?, avatarColor: String?) async throws -> ChildDto { try await store.updateChild(childId, displayName: displayName, avatarColor: avatarColor) }
    func pairingCode(childId: UUID) async throws -> PairingCodeResponse { try await store.pairingCode(childId: childId) }
    func revokeDevices(childId: UUID) async throws { try await store.revokeDevices(childId: childId) }
    func invite(email: String?) async throws -> InviteResponse { await store.invite() }
}

struct DemoLoanService: LoanService {
    let store: DemoStore

    func dashboard() async throws -> Dashboard { await store.dashboard() }
    func preview(_ input: LoanTermsInput) async throws -> SchedulePreview { await store.preview(input) }
    func create(_ input: LoanTermsInput) async throws -> LoanDetail { try await store.createLoan(input) }
    func parentLoans(status: LoanStatus?, childId: UUID?) async throws -> [LoanSummary] { await store.loanSummaries(status: status, childId: childId) }
    func loan(_ id: UUID) async throws -> LoanDetail { try await store.loanDetail(id) }
    func updateLoan(_ id: UUID, title: String?, sendReminders: Bool?, sendReceipts: Bool?) async throws -> LoanDetail { try await store.updateLoan(id, title: title, sendReminders: sendReminders, sendReceipts: sendReceipts) }
    func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate) async throws -> LoanDetail { try await store.updateInstallment(loanId: loanId, installmentId: installmentId, dueDate: dueDate) }
    func cancel(_ id: UUID) async throws -> LoanDetail { try await store.cancelLoan(id) }
    func recordPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> Payment { try await store.recordLoanPayment(loanId: loanId, amount: amount, paidOn: paidOn, note: note) }
    func payments(loanId: UUID) async throws -> [Payment] { try await store.loanPayments(loanId) }
    func waiveFee(loanId: UUID, lateFeeId: UUID) async throws -> LoanDetail { try await store.waiveLoanFee(loanId: loanId, lateFeeId: lateFeeId) }
    func myLoans() async throws -> [LoanSummary] { await store.myLoanSummaries() }
    func myLoan(_ id: UUID) async throws -> LoanDetail { try await store.myLoanDetail(id) }
}

struct DemoBillService: BillService {
    let store: DemoStore

    func bills(status: BillStatus?, childId: UUID?) async throws -> [BillSummary] { await store.billSummaries(status: status, childId: childId) }
    func bill(_ id: UUID) async throws -> BillDetail { try await store.billDetail(id) }
    func create(_ input: BillInput) async throws -> BillDetail { try await store.createBill(input) }
    func update(_ id: UUID, title: String?, amount: Decimal?, sendReminders: Bool?, sendReceipts: Bool?) async throws -> BillDetail { try await store.updateBill(id, title: title, amount: amount, sendReminders: sendReminders, sendReceipts: sendReceipts) }
    func end(_ id: UUID) async throws -> BillDetail { try await store.endBill(id) }
    func recordPayment(billId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> BillPayment { try await store.recordBillPayment(billId: billId, amount: amount, paidOn: paidOn, note: note) }
    func waiveFee(billId: UUID, lateFeeId: UUID) async throws -> BillDetail { try await store.waiveBillFee(billId: billId, lateFeeId: lateFeeId) }
}

struct DemoNotificationService: NotificationService {
    let store: DemoStore

    func notifications(unreadOnly: Bool) async throws -> [AppNotification] { await store.notifications(unreadOnly: unreadOnly) }
    func markRead(_ id: UUID) async throws { await store.markRead(id) }
    func markAllRead() async throws { await store.markAllRead() }
    /// Demo mode never registers for push, so device calls are intentionally no-ops.
    func registerDevice(apnsToken: String, environment: String) async throws {}
    func unregisterDevice(apnsToken: String) async throws {}
}
