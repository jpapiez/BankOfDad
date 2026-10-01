import Foundation

/// The service surface every screen talks to. The live implementations call the API; the demo
/// implementations (`Core/Demo`) answer from a local, in-memory store with no networking at all.
///
/// Protocol requirements spell out every parameter; the convenience overloads live in extensions so
/// conformances stay small and a default argument can never recurse into itself.

protocol FamilyService: Sendable {
    func family() async throws -> FamilyDto
    func updateFamily(name: String?, timeZone: String?) async throws -> FamilyDto
    func addChild(displayName: String, avatarColor: String?) async throws -> ChildDto
    func updateChild(_ childId: UUID, displayName: String?, avatarColor: String?) async throws -> ChildDto
    func pairingCode(childId: UUID) async throws -> PairingCodeResponse
    func revokeDevices(childId: UUID) async throws
    func invite(email: String?) async throws -> InviteResponse
}

protocol LoanService: Sendable {
    func dashboard() async throws -> Dashboard
    func preview(_ input: LoanTermsInput) async throws -> SchedulePreview
    func create(_ input: LoanTermsInput) async throws -> LoanDetail
    func parentLoans(status: LoanStatus?, childId: UUID?) async throws -> [LoanSummary]
    func loan(_ id: UUID) async throws -> LoanDetail
    func updateLoan(_ id: UUID, title: String?, sendReminders: Bool?, sendReceipts: Bool?) async throws -> LoanDetail
    func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate) async throws -> LoanDetail
    func cancel(_ id: UUID) async throws -> LoanDetail
    func recordPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> Payment
    func payments(loanId: UUID) async throws -> [Payment]
    func waiveFee(loanId: UUID, lateFeeId: UUID) async throws -> LoanDetail
    func myLoans() async throws -> [LoanSummary]
    func myLoan(_ id: UUID) async throws -> LoanDetail
}

extension LoanService {
    func parentLoans(childId: UUID?) async throws -> [LoanSummary] { try await parentLoans(status: nil, childId: childId) }
    func updateLoan(_ id: UUID, sendReminders: Bool?, sendReceipts: Bool?) async throws -> LoanDetail {
        try await updateLoan(id, title: nil, sendReminders: sendReminders, sendReceipts: sendReceipts)
    }
}

protocol BillService: Sendable {
    func bills(status: BillStatus?, childId: UUID?) async throws -> [BillSummary]
    func bill(_ id: UUID) async throws -> BillDetail
    func create(_ input: BillInput) async throws -> BillDetail
    func update(_ id: UUID, title: String?, amount: Decimal?, sendReminders: Bool?, sendReceipts: Bool?) async throws -> BillDetail
    func end(_ id: UUID) async throws -> BillDetail
    func recordPayment(billId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> BillPayment
    func waiveFee(billId: UUID, lateFeeId: UUID) async throws -> BillDetail
}

extension BillService {
    func bills() async throws -> [BillSummary] { try await bills(status: nil, childId: nil) }
    func bills(childId: UUID?) async throws -> [BillSummary] { try await bills(status: nil, childId: childId) }
    func bills(status: BillStatus?) async throws -> [BillSummary] { try await bills(status: status, childId: nil) }
    func update(_ id: UUID, title: String?, amount: Decimal?) async throws -> BillDetail {
        try await update(id, title: title, amount: amount, sendReminders: nil, sendReceipts: nil)
    }
    func update(_ id: UUID, sendReminders: Bool?, sendReceipts: Bool?) async throws -> BillDetail {
        try await update(id, title: nil, amount: nil, sendReminders: sendReminders, sendReceipts: sendReceipts)
    }
}

protocol NotificationService: Sendable {
    func notifications(unreadOnly: Bool) async throws -> [AppNotification]
    func markRead(_ id: UUID) async throws
    func markAllRead() async throws
    func registerDevice(apnsToken: String, environment: String) async throws
    func unregisterDevice(apnsToken: String) async throws
}

extension NotificationService {
    func notifications() async throws -> [AppNotification] { try await notifications(unreadOnly: false) }
}
