import Foundation

/// Actor facade over `DemoEngine`.
///
/// Holding the sample data in an actor lets the demo services stay `Sendable` value types, so the
/// view models can fan out with `async let` exactly as they do against the live API.
actor DemoStore {
    private let referenceDate: Date
    private var engine: DemoEngine
    private var role: Role = .parent
    private var activeChildId: UUID?

    init(referenceDate: Date = Date()) {
        self.referenceDate = referenceDate
        self.engine = DemoEngine(data: DemoSeed.make(referenceDate: referenceDate), now: referenceDate)
    }

    // MARK: - Session

    /// Child identity used to scope kid-facing reads; `nil` while exploring as a parent.
    private var childScope: UUID? { role == .child ? activeChildId : nil }

    func setRole(_ role: Role, childId: UUID?) {
        self.role = role
        if role == .child {
            activeChildId = childId ?? engine.data.children.first?.id
        }
    }

    func children() -> [DemoChild] { engine.data.children }

    func currency() -> String { engine.currency }

    func parentUser() -> UserDto { engine.parentUser() }

    func childUser(_ childId: UUID) -> UserDto? { engine.childUser(childId) }

    func activeChild() -> DemoChild? {
        guard let activeChildId else { return engine.data.children.first }
        return engine.data.children.first { $0.id == activeChildId } ?? engine.data.children.first
    }

    func reset() {
        engine = DemoEngine(data: DemoSeed.make(referenceDate: referenceDate), now: referenceDate)
        if let activeChildId, !engine.data.children.contains(where: { $0.id == activeChildId }) {
            self.activeChildId = engine.data.children.first?.id
        }
    }

    // MARK: - Family

    func family() -> FamilyDto { engine.family() }
    func updateFamily(name: String?, timeZone: String?) -> FamilyDto { engine.updateFamily(name: name, timeZone: timeZone) }
    func addChild(displayName: String, avatarColor: String?) -> ChildDto { engine.addChild(displayName: displayName, avatarColor: avatarColor) }
    func updateChild(_ childId: UUID, displayName: String?, avatarColor: String?) throws -> ChildDto { try engine.updateChild(childId, displayName: displayName, avatarColor: avatarColor) }
    func revokeDevices(childId: UUID) throws { try engine.revokeDevices(childId: childId) }
    func pairingCode(childId: UUID) throws -> PairingCodeResponse { try engine.pairingCode(childId: childId) }
    func invite() -> InviteResponse { engine.invite() }

    // MARK: - Loans

    func dashboard() -> Dashboard { engine.dashboard() }
    func preview(_ input: LoanTermsInput) -> SchedulePreview { engine.preview(input) }
    func createLoan(_ input: LoanTermsInput) throws -> LoanDetail { try engine.createLoan(input) }
    func loanSummaries(status: LoanStatus?, childId: UUID?) -> [LoanSummary] { engine.loanSummaries(status: status, childId: childId) }
    func loanDetail(_ id: UUID) throws -> LoanDetail { try engine.loanDetail(id) }
    func updateLoan(_ id: UUID, title: String?, sendReminders: Bool?, sendReceipts: Bool?) throws -> LoanDetail { try engine.updateLoan(id, title: title, sendReminders: sendReminders, sendReceipts: sendReceipts) }
    func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate) throws -> LoanDetail { try engine.updateInstallment(loanId: loanId, installmentId: installmentId, dueDate: dueDate) }
    func cancelLoan(_ id: UUID) throws -> LoanDetail { try engine.cancelLoan(id) }
    func loanPayments(_ id: UUID) throws -> [Payment] { try engine.loanPayments(id) }
    func recordLoanPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) throws -> Payment { try engine.recordLoanPayment(loanId: loanId, amount: amount, paidOn: paidOn, note: note) }
    func waiveLoanFee(loanId: UUID, lateFeeId: UUID) throws -> LoanDetail { try engine.waiveLoanFee(loanId: loanId, lateFeeId: lateFeeId) }
    func myLoanSummaries() -> [LoanSummary] { engine.myLoanSummaries(childScope: childScope) }
    func myLoanDetail(_ id: UUID) throws -> LoanDetail { try engine.myLoanDetail(id, childScope: childScope) }

    // MARK: - Bills

    func billSummaries(status: BillStatus?, childId: UUID?) -> [BillSummary] { engine.billSummaries(status: status, childId: childId, childScope: childScope) }
    func billDetail(_ id: UUID) throws -> BillDetail { try engine.billDetail(id, childScope: childScope) }
    func createBill(_ input: BillInput) throws -> BillDetail { try engine.createBill(input) }
    func updateBill(_ id: UUID, title: String?, amount: Decimal?, sendReminders: Bool?, sendReceipts: Bool?) throws -> BillDetail { try engine.updateBill(id, title: title, amount: amount, sendReminders: sendReminders, sendReceipts: sendReceipts) }
    func endBill(_ id: UUID) throws -> BillDetail { try engine.endBill(id) }
    func recordBillPayment(billId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) throws -> BillPayment { try engine.recordBillPayment(billId: billId, amount: amount, paidOn: paidOn, note: note) }
    func waiveBillFee(billId: UUID, lateFeeId: UUID) throws -> BillDetail { try engine.waiveBillFee(billId: billId, lateFeeId: lateFeeId) }

    // MARK: - Notifications

    func notifications(unreadOnly: Bool) -> [AppNotification] { engine.notifications(unreadOnly: unreadOnly, childScope: childScope) }
    func markRead(_ id: UUID) { engine.markRead(id) }
    func markAllRead() { engine.markAllRead(childScope: childScope) }
}
