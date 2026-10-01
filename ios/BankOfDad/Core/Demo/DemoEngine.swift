import Foundation

/// Pure, local replacement for the backend's loan/bill logic.
///
/// The engine owns a `DemoData` value and performs the same arithmetic the server does, so every
/// screen in the app stays self-consistent: recording a payment on a loan immediately changes the
/// parent dashboard, the child detail screen, the kid's "My loans" list and the receipt in the kid's
/// Inbox. It is a plain value type so both `DemoSeed` (to build coherent sample data) and `DemoStore`
/// (to serve the running app) can drive exactly the same code paths.
struct DemoEngine {
    var data: DemoData
    /// The engine's "now". Everything in demo mode is relative to this instant.
    let now: Date

    init(data: DemoData, now: Date) {
        self.data = data
        self.now = now
    }

    // MARK: - Session

    var currency: String { data.currency }

    func parentUser() -> UserDto { data.parent }

    func childUser(_ childId: UUID) -> UserDto? {
        guard let child = data.children.first(where: { $0.id == childId }) else { return nil }
        return UserDto(id: child.id, familyId: data.familyId, role: .child, displayName: child.displayName, email: nil)
    }

    // MARK: - Clock

    private var today: CalendarDate { CalendarDate(now, timeZone: DemoMath.calendar.timeZone) }

    // MARK: - Family

    func family() -> FamilyDto {
        FamilyDto(
            id: data.familyId,
            name: data.familyName,
            timeZone: data.timeZone,
            currency: data.currency,
            parents: [data.parent],
            children: data.children.map(childDto)
        )
    }

    mutating func updateFamily(name: String?, timeZone: String?) -> FamilyDto {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { data.familyName = name }
        if let timeZone, !timeZone.isEmpty { data.timeZone = timeZone }
        return family()
    }

    mutating func addChild(displayName: String, avatarColor: String?) -> ChildDto {
        let child = DemoChild(id: UUID(), displayName: displayName, avatarColor: avatarColor, pairedDeviceCount: 0)
        data.children.append(child)
        return childDto(child)
    }

    mutating func updateChild(_ childId: UUID, displayName: String?, avatarColor: String?) throws -> ChildDto {
        guard let index = data.children.firstIndex(where: { $0.id == childId }) else { throw DemoEngine.notFound("Child") }
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { data.children[index].displayName = displayName }
        if let avatarColor { data.children[index].avatarColor = avatarColor.isEmpty ? nil : avatarColor }
        return childDto(data.children[index])
    }

    mutating func revokeDevices(childId: UUID) throws {
        guard let index = data.children.firstIndex(where: { $0.id == childId }) else { throw DemoEngine.notFound("Child") }
        data.children[index].pairedDeviceCount = 0
    }

    func pairingCode(childId: UUID) throws -> PairingCodeResponse {
        guard data.children.contains(where: { $0.id == childId }) else { throw DemoEngine.notFound("Child") }
        let code = DemoSeed.pairingCode(for: childId)
        return PairingCodeResponse(code: code, qrPayload: "bankofdad://pair?code=\(code)", expiresAt: now.addingTimeInterval(15 * 60))
    }

    func invite() -> InviteResponse {
        InviteResponse(inviteCode: DemoSeed.inviteCode, expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60))
    }

    private func childDto(_ child: DemoChild) -> ChildDto {
        ChildDto(id: child.id, displayName: child.displayName, avatarColor: child.avatarColor, pairedDeviceCount: child.pairedDeviceCount)
    }

    private func childName(_ id: UUID) -> String {
        data.children.first(where: { $0.id == id })?.displayName ?? "Child"
    }

    // MARK: - Loans

    mutating func loanSummaries(status: LoanStatus?, childId: UUID?) -> [LoanSummary] {
        accrue()
        return data.loans
            .filter { loan in
                if let status, status != .unknown, loan.status != status { return false }
                if let childId, loan.childId != childId { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map(loanSummary)
    }

    mutating func myLoanSummaries(childScope: UUID?) -> [LoanSummary] {
        loanSummaries(status: nil, childId: childScope)
    }

    mutating func loanDetail(_ id: UUID) throws -> LoanDetail {
        accrue()
        guard let loan = data.loans.first(where: { $0.id == id }) else { throw DemoEngine.notFound("Loan") }
        return loanDetail(loan)
    }

    mutating func myLoanDetail(_ id: UUID, childScope: UUID?) throws -> LoanDetail {
        let detail = try loanDetail(id)
        guard childScope == nil || detail.childId == childScope else { throw DemoEngine.notFound("Loan") }
        return detail
    }

    func preview(_ input: LoanTermsInput) -> SchedulePreview {
        let rows = DemoMath.schedule(
            principal: input.principal,
            annualRate: input.annualRate,
            interestEnabled: input.interestEnabled,
            frequency: input.frequency,
            installmentCount: input.installmentCount,
            firstDueDate: input.firstDueDate
        )
        return SchedulePreview(
            installmentAmount: rows.first?.amountDue ?? 0,
            totalInterest: rows.reduce(0) { $0 + $1.interestDue },
            totalRepayable: rows.reduce(0) { $0 + $1.amountDue },
            installments: rows.map { SchedulePreviewItem(seq: $0.seq, dueDate: $0.dueDate, principalDue: $0.principalDue, interestDue: $0.interestDue, amountDue: $0.amountDue) }
        )
    }

    mutating func createLoan(_ input: LoanTermsInput) throws -> LoanDetail {
        guard data.children.contains(where: { $0.id == input.childId }) else { throw DemoEngine.notFound("Child") }
        guard input.principal > 0 else { throw DemoEngine.validation("Amount must be greater than zero.") }
        guard input.installmentCount > 0 else { throw DemoEngine.validation("Add at least one payment.") }

        let rows = DemoMath.schedule(
            principal: input.principal,
            annualRate: input.annualRate,
            interestEnabled: input.interestEnabled,
            frequency: input.frequency,
            installmentCount: input.installmentCount,
            firstDueDate: input.firstDueDate
        )
        let loan = DemoLoan(
            id: UUID(),
            childId: input.childId,
            title: input.title,
            principal: input.principal,
            interestEnabled: input.interestEnabled,
            annualRate: input.annualRate,
            frequency: input.frequency,
            installmentCount: input.installmentCount,
            firstDueDate: input.firstDueDate,
            lateFeeFlat: input.lateFeeFlat,
            lateFeePercent: input.lateFeePercent,
            lateFeeGraceDays: input.lateFeeGraceDays,
            sendReminders: input.sendReminders,
            sendReceipts: input.sendReceipts,
            status: .active,
            createdAt: now,
            installments: rows.map { DemoInstallment(id: UUID(), seq: $0.seq, dueDate: $0.dueDate, principalDue: $0.principalDue, interestDue: $0.interestDue) }
        )
        data.loans.append(loan)
        addNotification(
            childId: loan.childId,
            type: .loanCreated,
            title: "New loan: \(loan.title)",
            body: "\(AppFormatters.money(loan.principal, currencyCode: data.currency)) over \(loan.installmentCount) payments.",
            loanId: loan.id,
            billId: nil,
            createdAt: now
        )
        return loanDetail(loan)
    }

    mutating func updateLoan(_ id: UUID, title: String?, sendReminders: Bool?, sendReceipts: Bool?) throws -> LoanDetail {
        guard let index = data.loans.firstIndex(where: { $0.id == id }) else { throw DemoEngine.notFound("Loan") }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { data.loans[index].title = title }
        if let sendReminders { data.loans[index].sendReminders = sendReminders }
        if let sendReceipts { data.loans[index].sendReceipts = sendReceipts }
        accrue()
        return loanDetail(data.loans[index])
    }

    mutating func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate) throws -> LoanDetail {
        guard let loanIndex = data.loans.firstIndex(where: { $0.id == loanId }) else { throw DemoEngine.notFound("Loan") }
        guard let index = data.loans[loanIndex].installments.firstIndex(where: { $0.id == installmentId }) else { throw DemoEngine.notFound("Installment") }
        data.loans[loanIndex].installments[index].dueDate = dueDate
        accrue()
        return loanDetail(data.loans[loanIndex])
    }

    mutating func cancelLoan(_ id: UUID) throws -> LoanDetail {
        guard let index = data.loans.firstIndex(where: { $0.id == id }) else { throw DemoEngine.notFound("Loan") }
        guard data.loans[index].status == .active else { throw DemoEngine.validation("This loan is already closed.") }
        data.loans[index].status = .cancelled
        return loanDetail(data.loans[index])
    }

    func loanPayments(_ id: UUID) throws -> [Payment] {
        guard let loan = data.loans.first(where: { $0.id == id }) else { throw DemoEngine.notFound("Loan") }
        return loan.payments.sorted { $0.createdAt > $1.createdAt }.map(payment)
    }

    @discardableResult
    mutating func recordLoanPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) throws -> Payment {
        accrue()
        guard let index = data.loans.firstIndex(where: { $0.id == loanId }) else { throw DemoEngine.notFound("Loan") }
        guard data.loans[index].status == .active else { throw DemoEngine.validation("This loan is already closed.") }
        let amount = DemoMath.round(amount)
        guard amount > 0 else { throw DemoEngine.validation("Enter an amount greater than zero.") }
        guard amount <= data.loans[index].balance else { throw DemoEngine.validation("That is more than the remaining balance.") }

        var remaining = amount
        var allocations: [Allocation] = []

        // Late fees first (oldest assessed first), then each installment: interest before principal.
        let feeOrder = data.loans[index].lateFees.enumerated()
            .filter { $0.element.remaining > 0 }
            .sorted { $0.element.assessedAt < $1.element.assessedAt }
            .map(\.offset)
        for feeIndex in feeOrder where remaining > 0 {
            let take = min(remaining, data.loans[index].lateFees[feeIndex].remaining)
            guard take > 0 else { continue }
            data.loans[index].lateFees[feeIndex].amountPaid += take
            remaining -= take
            allocations.append(Allocation(target: .lateFee, installmentSeq: data.loans[index].lateFees[feeIndex].installmentSeq, lateFeeId: data.loans[index].lateFees[feeIndex].id, amount: take))
        }

        for installmentIndex in data.loans[index].installments.indices where remaining > 0 {
            let installment = data.loans[index].installments[installmentIndex]
            let interestOwed = max(0, installment.interestDue - installment.interestPaid)
            if interestOwed > 0 {
                let take = min(remaining, interestOwed)
                data.loans[index].installments[installmentIndex].interestPaid += take
                remaining -= take
                allocations.append(Allocation(target: .interest, installmentSeq: installment.seq, lateFeeId: nil, amount: take))
            }
            let principalOwed = max(0, installment.principalDue - data.loans[index].installments[installmentIndex].principalPaid)
            if remaining > 0 && principalOwed > 0 {
                let take = min(remaining, principalOwed)
                data.loans[index].installments[installmentIndex].principalPaid += take
                remaining -= take
                allocations.append(Allocation(target: .principal, installmentSeq: installment.seq, lateFeeId: nil, amount: take))
            }
        }

        let record = DemoPayment(
            id: UUID(),
            amount: amount,
            paidOn: paidOn,
            note: note?.isEmpty == true ? nil : note,
            recordedByName: data.parent.displayName,
            createdAt: now,
            allocations: allocations
        )
        data.loans[index].payments.append(record)

        if data.loans[index].balance <= 0 {
            data.loans[index].status = .paidOff
        }
        if data.loans[index].sendReceipts {
            addNotification(
                childId: data.loans[index].childId,
                type: .receipt,
                title: "Payment received",
                body: "\(AppFormatters.money(amount, currencyCode: data.currency)) toward \(data.loans[index].title).",
                loanId: loanId,
                billId: nil,
                createdAt: now
            )
        }
        return payment(record)
    }

    mutating func waiveLoanFee(loanId: UUID, lateFeeId: UUID) throws -> LoanDetail {
        guard let loanIndex = data.loans.firstIndex(where: { $0.id == loanId }) else { throw DemoEngine.notFound("Loan") }
        guard let index = data.loans[loanIndex].lateFees.firstIndex(where: { $0.id == lateFeeId }) else { throw DemoEngine.notFound("Late fee") }
        guard data.loans[loanIndex].lateFees[index].waivedAt == nil else { throw DemoEngine.validation("That fee is already waived.") }
        data.loans[loanIndex].lateFees[index].waivedAt = now
        if data.loans[loanIndex].balance <= 0 { data.loans[loanIndex].status = .paidOff }
        return loanDetail(data.loans[loanIndex])
    }

    // MARK: - Bills

    mutating func billSummaries(status: BillStatus?, childId: UUID?, childScope: UUID?) -> [BillSummary] {
        accrue()
        let scopedChildId = childScope ?? childId
        return data.bills
            .filter { bill in
                if let status, status != .unknown, bill.status != status { return false }
                if let scopedChildId, bill.childId != scopedChildId { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map(billSummary)
    }

    mutating func billDetail(_ id: UUID, childScope: UUID?) throws -> BillDetail {
        accrue()
        guard let bill = data.bills.first(where: { $0.id == id }) else { throw DemoEngine.notFound("Bill") }
        guard childScope == nil || bill.childId == childScope else { throw DemoEngine.notFound("Bill") }
        return billDetail(bill)
    }

    mutating func createBill(_ input: BillInput) throws -> BillDetail {
        guard data.children.contains(where: { $0.id == input.childId }) else { throw DemoEngine.notFound("Child") }
        guard input.amount > 0 else { throw DemoEngine.validation("Amount must be greater than zero.") }
        let bill = DemoBill(
            id: UUID(),
            childId: input.childId,
            title: input.title,
            amount: input.amount,
            frequency: input.frequency,
            firstDueDate: input.firstDueDate,
            lateFeeFlat: input.lateFeeFlat,
            lateFeePercent: input.lateFeePercent,
            lateFeeGraceDays: input.lateFeeGraceDays,
            sendReminders: input.sendReminders,
            sendReceipts: input.sendReceipts,
            status: .active,
            createdAt: now,
            endedAt: nil
        )
        data.bills.append(bill)
        addNotification(
            childId: bill.childId,
            type: .billCreated,
            title: "New bill: \(bill.title)",
            body: "\(AppFormatters.money(bill.amount, currencyCode: data.currency)) \(bill.frequency.label.lowercased()).",
            loanId: nil,
            billId: bill.id,
            createdAt: now
        )
        accrue()
        guard let stored = data.bills.first(where: { $0.id == bill.id }) else { throw DemoEngine.notFound("Bill") }
        return billDetail(stored)
    }

    mutating func updateBill(_ id: UUID, title: String?, amount: Decimal?, sendReminders: Bool?, sendReceipts: Bool?) throws -> BillDetail {
        guard let index = data.bills.firstIndex(where: { $0.id == id }) else { throw DemoEngine.notFound("Bill") }
        if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { data.bills[index].title = title }
        if let amount {
            guard amount > 0 else { throw DemoEngine.validation("Amount must be greater than zero.") }
            data.bills[index].amount = amount
            // Repricing only affects charges that are not due yet, and never drops below what was paid.
            let today = today
            for chargeIndex in data.bills[index].charges.indices where data.bills[index].charges[chargeIndex].dueDate > today {
                let paid = data.bills[index].charges[chargeIndex].amountPaid
                data.bills[index].charges[chargeIndex].amount = max(amount, paid)
            }
        }
        if let sendReminders { data.bills[index].sendReminders = sendReminders }
        if let sendReceipts { data.bills[index].sendReceipts = sendReceipts }
        accrue()
        return billDetail(data.bills[index])
    }

    mutating func endBill(_ id: UUID) throws -> BillDetail {
        accrue()
        guard let index = data.bills.firstIndex(where: { $0.id == id }) else { throw DemoEngine.notFound("Bill") }
        guard data.bills[index].status == .active else { throw DemoEngine.validation("This bill already ended.") }
        data.bills[index].status = .ended
        data.bills[index].endedAt = now
        let today = today
        data.bills[index].charges.removeAll { $0.dueDate > today && $0.amountPaid <= 0 }
        for chargeIndex in data.bills[index].charges.indices where data.bills[index].charges[chargeIndex].dueDate > today {
            data.bills[index].charges[chargeIndex].amount = data.bills[index].charges[chargeIndex].amountPaid
            data.bills[index].charges[chargeIndex].closed = true
        }
        return billDetail(data.bills[index])
    }

    @discardableResult
    mutating func recordBillPayment(billId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) throws -> BillPayment {
        accrue()
        guard let index = data.bills.firstIndex(where: { $0.id == billId }) else { throw DemoEngine.notFound("Bill") }
        let amount = DemoMath.round(amount)
        guard amount > 0 else { throw DemoEngine.validation("Enter an amount greater than zero.") }
        let payable = billPayable(data.bills[index])
        guard amount <= payable else { throw DemoEngine.validation("That is more than this bill can accept right now.") }

        var remaining = amount
        var allocations: [BillAllocation] = []

        let feeOrder = data.bills[index].lateFees.enumerated()
            .filter { $0.element.remaining > 0 }
            .sorted { $0.element.assessedAt < $1.element.assessedAt }
            .map(\.offset)
        for feeIndex in feeOrder where remaining > 0 {
            let take = min(remaining, data.bills[index].lateFees[feeIndex].remaining)
            guard take > 0 else { continue }
            data.bills[index].lateFees[feeIndex].amountPaid += take
            remaining -= take
            allocations.append(BillAllocation(target: .lateFee, chargeId: data.bills[index].lateFees[feeIndex].chargeId, chargeDueDate: data.bills[index].lateFees[feeIndex].chargeDueDate, lateFeeId: data.bills[index].lateFees[feeIndex].id, amount: take))
        }

        for chargeIndex in data.bills[index].charges.indices.sorted(by: { data.bills[index].charges[$0].seq < data.bills[index].charges[$1].seq }) where remaining > 0 {
            let owed = data.bills[index].charges[chargeIndex].remaining
            guard owed > 0 else { continue }
            let take = min(remaining, owed)
            data.bills[index].charges[chargeIndex].amountPaid += take
            remaining -= take
            allocations.append(BillAllocation(target: .charge, chargeId: data.bills[index].charges[chargeIndex].id, chargeDueDate: data.bills[index].charges[chargeIndex].dueDate, lateFeeId: nil, amount: take))
        }

        let record = DemoBillPayment(
            id: UUID(),
            amount: amount,
            paidOn: paidOn,
            note: note?.isEmpty == true ? nil : note,
            recordedByName: data.parent.displayName,
            createdAt: now,
            allocations: allocations
        )
        data.bills[index].payments.append(record)
        if data.bills[index].sendReceipts {
            addNotification(
                childId: data.bills[index].childId,
                type: .receipt,
                title: "Payment received",
                body: "\(AppFormatters.money(amount, currencyCode: data.currency)) toward \(data.bills[index].title).",
                loanId: nil,
                billId: billId,
                createdAt: now
            )
        }
        return billPayment(record)
    }

    mutating func waiveBillFee(billId: UUID, lateFeeId: UUID) throws -> BillDetail {
        guard let billIndex = data.bills.firstIndex(where: { $0.id == billId }) else { throw DemoEngine.notFound("Bill") }
        guard let index = data.bills[billIndex].lateFees.firstIndex(where: { $0.id == lateFeeId }) else { throw DemoEngine.notFound("Late fee") }
        guard data.bills[billIndex].lateFees[index].waivedAt == nil else { throw DemoEngine.validation("That fee is already waived.") }
        data.bills[billIndex].lateFees[index].waivedAt = now
        return billDetail(data.bills[billIndex])
    }

    // MARK: - Notifications

    mutating func notifications(unreadOnly: Bool, childScope: UUID?) -> [AppNotification] {
        accrue()
        return data.notifications
            .filter { notification in
                if let childScope, notification.childId != childScope { return false }
                if unreadOnly && notification.readAt != nil { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .map { AppNotification(id: $0.id, type: $0.type, title: $0.title, body: $0.body, loanId: $0.loanId, createdAt: $0.createdAt, readAt: $0.readAt, billId: $0.billId) }
    }

    mutating func markRead(_ id: UUID) {
        guard let index = data.notifications.firstIndex(where: { $0.id == id }) else { return }
        if data.notifications[index].readAt == nil { data.notifications[index].readAt = now }
    }

    mutating func markAllRead(childScope: UUID?) {
        for index in data.notifications.indices where data.notifications[index].readAt == nil {
            if let childScope, data.notifications[index].childId != childScope { continue }
            data.notifications[index].readAt = now
        }
    }

    mutating private func addNotification(childId: UUID, type: NotificationType, title: String, body: String, loanId: UUID?, billId: UUID?, createdAt: Date) {
        data.notifications.append(DemoNotification(id: UUID(), childId: childId, type: type, title: title, body: body, loanId: loanId, billId: billId, createdAt: createdAt, readAt: nil))
    }

    // MARK: - Dashboard

    mutating func dashboard() -> Dashboard {
        accrue()
        let today = today
        let activeLoans = data.loans.filter { $0.status == .active }
        let lateInstallments = activeLoans.reduce(0) { total, loan in
            total + loan.installments.filter { DemoMath.dueStatus(remaining: $0.remaining, dueDate: $0.dueDate, today: today, graceDays: loan.lateFeeGraceDays) == .late }.count
        }
        let upcoming = activeLoans.compactMap { loan -> UpcomingItem? in
            guard let next = loan.installments.first(where: { $0.remaining > 0 }) else { return nil }
            return UpcomingItem(loanId: loan.id, loanTitle: loan.title, childName: childName(loan.childId), dueDate: next.dueDate, amountDue: next.remaining)
        }.sorted { $0.dueDate < $1.dueDate }

        let activeBills = data.bills.filter { $0.status == .active }
        let lateBillCharges = activeBills.reduce(0) { total, bill in
            total + bill.charges.filter { DemoMath.dueStatus(remaining: $0.remaining, dueDate: $0.dueDate, today: today, graceDays: bill.lateFeeGraceDays) == .late }.count
        }
        let upcomingBills = activeBills.compactMap { bill -> UpcomingBillItem? in
            guard let next = bill.charges.first(where: { $0.remaining > 0 }) else { return nil }
            return UpcomingBillItem(billId: bill.id, billTitle: bill.title, childName: childName(bill.childId), dueDate: next.dueDate, amountDue: next.remaining)
        }.sorted { $0.dueDate < $1.dueDate }

        return Dashboard(
            totalOutstanding: activeLoans.reduce(0) { $0 + $1.balance },
            activeLoans: activeLoans.count,
            lateInstallments: lateInstallments,
            upcoming: Array(upcoming.prefix(5)),
            activeBills: activeBills.count,
            lateBillCharges: lateBillCharges,
            upcomingBills: Array(upcomingBills.prefix(5))
        )
    }

    // MARK: - Accrual

    /// Brings the sample data up to date with "today": generates the bill charges that are due,
    /// assesses late fees on overdue items and closes out loans that have been fully repaid. Running
    /// this on every read keeps the demo coherent no matter how long the app stays open.
    mutating private func accrue() {
        let today = today
        for index in data.loans.indices {
            guard data.loans[index].status == .active else { continue }
            for installment in data.loans[index].installments {
                let status = DemoMath.dueStatus(remaining: installment.remaining, dueDate: installment.dueDate, today: today, graceDays: data.loans[index].lateFeeGraceDays)
                guard status == .late else { continue }
                guard !data.loans[index].lateFees.contains(where: { $0.installmentId == installment.id }) else { continue }
                let amount = DemoMath.lateFeeAmount(flat: data.loans[index].lateFeeFlat, percent: data.loans[index].lateFeePercent, base: installment.remaining)
                guard amount > 0 else { continue }
                let assessedAt = assessmentDate(dueDate: installment.dueDate, graceDays: data.loans[index].lateFeeGraceDays)
                data.loans[index].lateFees.append(DemoLateFee(id: UUID(), installmentId: installment.id, installmentSeq: installment.seq, amount: amount, assessedAt: assessedAt))
                addNotification(
                    childId: data.loans[index].childId,
                    type: .lateFee,
                    title: "Late fee added",
                    body: "\(AppFormatters.money(amount, currencyCode: data.currency)) on \(data.loans[index].title).",
                    loanId: data.loans[index].id,
                    billId: nil,
                    createdAt: assessedAt
                )
            }
            if data.loans[index].balance <= 0 { data.loans[index].status = .paidOff }
        }

        for index in data.bills.indices {
            if data.bills[index].status == .active { generateCharges(billIndex: index, today: today) }
            for charge in data.bills[index].charges {
                let status = DemoMath.dueStatus(remaining: charge.remaining, dueDate: charge.dueDate, today: today, graceDays: data.bills[index].lateFeeGraceDays)
                guard status == .late else { continue }
                guard !data.bills[index].lateFees.contains(where: { $0.chargeId == charge.id }) else { continue }
                let amount = DemoMath.lateFeeAmount(flat: data.bills[index].lateFeeFlat, percent: data.bills[index].lateFeePercent, base: charge.remaining)
                guard amount > 0 else { continue }
                let assessedAt = assessmentDate(dueDate: charge.dueDate, graceDays: data.bills[index].lateFeeGraceDays)
                data.bills[index].lateFees.append(DemoBillLateFee(id: UUID(), chargeId: charge.id, chargeDueDate: charge.dueDate, amount: amount, assessedAt: assessedAt))
                addNotification(
                    childId: data.bills[index].childId,
                    type: .lateFee,
                    title: "Late fee added",
                    body: "\(AppFormatters.money(amount, currencyCode: data.currency)) on \(data.bills[index].title).",
                    loanId: nil,
                    billId: data.bills[index].id,
                    createdAt: assessedAt
                )
            }
        }
    }

    private func assessmentDate(dueDate: CalendarDate, graceDays: Int) -> Date {
        let calendar = DemoMath.calendar
        let base = dueDate.date(in: calendar.timeZone)
        let assessed = calendar.date(byAdding: .day, value: max(0, graceDays) + 1, to: base) ?? base
        return min(assessed, now)
    }

    /// Mirrors the server scheduler: every charge due on or before today, plus the next upcoming one.
    mutating private func generateCharges(billIndex: Int, today: CalendarDate) {
        let bill = data.bills[billIndex]
        var seq = (bill.charges.map(\.seq).max() ?? 0) + 1
        while true {
            let dueDate = DemoMath.dueDate(first: bill.firstDueDate, frequency: bill.frequency, seq: seq)
            let alreadyUpcoming = data.bills[billIndex].charges.contains { $0.dueDate > today }
            if dueDate > today && alreadyUpcoming { break }
            data.bills[billIndex].charges.append(DemoBillCharge(id: UUID(), seq: seq, dueDate: dueDate, amount: bill.amount))
            seq += 1
            if dueDate > today { break }
            if seq > 240 { break }
        }
    }

    // MARK: - Projections

    private func loanSummary(_ loan: DemoLoan) -> LoanSummary {
        let next = loan.status == .active ? loan.installments.first(where: { $0.remaining > 0 }) : nil
        return LoanSummary(
            id: loan.id,
            title: loan.title,
            childId: loan.childId,
            childName: childName(loan.childId),
            principal: loan.principal,
            status: loan.status,
            balance: loan.balance,
            amountPaid: loan.amountPaid,
            nextDueDate: next?.dueDate,
            nextAmountDue: next?.remaining,
            lateInstallments: lateCount(loan),
            createdAt: loan.createdAt
        )
    }

    private func lateCount(_ loan: DemoLoan) -> Int {
        guard loan.status == .active else { return 0 }
        let today = today
        return loan.installments.filter { DemoMath.dueStatus(remaining: $0.remaining, dueDate: $0.dueDate, today: today, graceDays: loan.lateFeeGraceDays) == .late }.count
    }

    private func loanDetail(_ loan: DemoLoan) -> LoanDetail {
        let today = today
        let next = loan.status == .active ? loan.installments.first(where: { $0.remaining > 0 }) : nil
        return LoanDetail(
            id: loan.id,
            title: loan.title,
            childId: loan.childId,
            childName: childName(loan.childId),
            principal: loan.principal,
            status: loan.status,
            balance: loan.balance,
            amountPaid: loan.amountPaid,
            nextDueDate: next?.dueDate,
            nextAmountDue: next?.remaining,
            lateInstallments: lateCount(loan),
            createdAt: loan.createdAt,
            interestEnabled: loan.interestEnabled,
            annualRate: loan.annualRate,
            frequency: loan.frequency,
            installmentCount: loan.installmentCount,
            firstDueDate: loan.firstDueDate,
            lateFeeFlat: loan.lateFeeFlat,
            lateFeePercent: loan.lateFeePercent,
            lateFeeGraceDays: loan.lateFeeGraceDays,
            sendReminders: loan.sendReminders,
            sendReceipts: loan.sendReceipts,
            totalInterest: loan.totalInterest,
            totalRepayable: loan.totalRepayable,
            outstandingFees: loan.outstandingFees,
            installments: loan.installments.map { installment in
                Installment(
                    id: installment.id,
                    seq: installment.seq,
                    dueDate: installment.dueDate,
                    principalDue: installment.principalDue,
                    interestDue: installment.interestDue,
                    amountDue: installment.amountDue,
                    principalPaid: installment.principalPaid,
                    interestPaid: installment.interestPaid,
                    remaining: installment.remaining,
                    status: loan.status == .cancelled ? .upcoming : DemoMath.dueStatus(remaining: installment.remaining, dueDate: installment.dueDate, today: today, graceDays: loan.lateFeeGraceDays)
                )
            },
            payments: loan.payments.sorted { $0.createdAt > $1.createdAt }.map(payment),
            lateFees: loan.lateFees.map { LateFee(id: $0.id, installmentId: $0.installmentId, installmentSeq: $0.installmentSeq, amount: $0.amount, amountPaid: $0.amountPaid, assessedAt: $0.assessedAt, waivedAt: $0.waivedAt) },
            termsSummary: DemoMath.loanTermsSummary(
                principal: loan.principal,
                interestEnabled: loan.interestEnabled,
                annualRate: loan.annualRate,
                frequency: loan.frequency,
                installmentCount: loan.installmentCount,
                installmentAmount: loan.installments.first?.amountDue ?? 0,
                lateFeeFlat: loan.lateFeeFlat,
                lateFeePercent: loan.lateFeePercent,
                graceDays: loan.lateFeeGraceDays,
                currency: data.currency
            )
        )
    }

    private func payment(_ payment: DemoPayment) -> Payment {
        Payment(id: payment.id, amount: payment.amount, paidOn: payment.paidOn, note: payment.note, recordedByName: payment.recordedByName, createdAt: payment.createdAt, allocations: payment.allocations)
    }

    private func billPayment(_ payment: DemoBillPayment) -> BillPayment {
        BillPayment(id: payment.id, amount: payment.amount, paidOn: payment.paidOn, note: payment.note, recordedByName: payment.recordedByName, createdAt: payment.createdAt, allocations: payment.allocations)
    }

    private func billBalance(_ bill: DemoBill) -> Decimal {
        let today = today
        let due = bill.charges.filter { $0.dueDate <= today }.reduce(0) { $0 + $1.remaining }
        return due + bill.outstandingFees
    }

    private func billUpcoming(_ bill: DemoBill) -> Decimal {
        let today = today
        return bill.charges.filter { $0.dueDate > today }.reduce(0) { $0 + $1.remaining }
    }

    private func billPayable(_ bill: DemoBill) -> Decimal {
        bill.charges.reduce(0) { $0 + $1.remaining } + bill.outstandingFees
    }

    private func billLateCount(_ bill: DemoBill) -> Int {
        let today = today
        return bill.charges.filter { DemoMath.dueStatus(remaining: $0.remaining, dueDate: $0.dueDate, today: today, graceDays: bill.lateFeeGraceDays) == .late }.count
    }

    private func billSummary(_ bill: DemoBill) -> BillSummary {
        let next = bill.charges.sorted { $0.seq < $1.seq }.first { $0.remaining > 0 }
        return BillSummary(
            id: bill.id,
            title: bill.title,
            childId: bill.childId,
            childName: childName(bill.childId),
            amount: bill.amount,
            frequency: bill.frequency,
            status: bill.status,
            balance: billBalance(bill),
            upcomingAmount: billUpcoming(bill),
            amountPaid: bill.amountPaid,
            nextDueDate: next?.dueDate,
            nextAmountDue: next?.remaining,
            lateCharges: billLateCount(bill),
            createdAt: bill.createdAt,
            endedAt: bill.endedAt
        )
    }

    private func billDetail(_ bill: DemoBill) -> BillDetail {
        let today = today
        let next = bill.charges.sorted { $0.seq < $1.seq }.first { $0.remaining > 0 }
        return BillDetail(
            id: bill.id,
            title: bill.title,
            childId: bill.childId,
            childName: childName(bill.childId),
            amount: bill.amount,
            frequency: bill.frequency,
            status: bill.status,
            balance: billBalance(bill),
            upcomingAmount: billUpcoming(bill),
            amountPaid: bill.amountPaid,
            nextDueDate: next?.dueDate,
            nextAmountDue: next?.remaining,
            lateCharges: billLateCount(bill),
            createdAt: bill.createdAt,
            endedAt: bill.endedAt,
            firstDueDate: bill.firstDueDate,
            lateFeeFlat: bill.lateFeeFlat,
            lateFeePercent: bill.lateFeePercent,
            lateFeeGraceDays: bill.lateFeeGraceDays,
            sendReminders: bill.sendReminders,
            sendReceipts: bill.sendReceipts,
            outstandingFees: bill.outstandingFees,
            charges: bill.charges.sorted { $0.seq < $1.seq }.map { charge in
                BillCharge(
                    id: charge.id,
                    seq: charge.seq,
                    dueDate: charge.dueDate,
                    amount: charge.amount,
                    amountPaid: charge.amountPaid,
                    remaining: charge.remaining,
                    status: DemoMath.dueStatus(remaining: charge.remaining, dueDate: charge.dueDate, today: today, graceDays: bill.lateFeeGraceDays)
                )
            },
            payments: bill.payments.sorted { $0.createdAt > $1.createdAt }.map(billPayment),
            lateFees: bill.lateFees.map { BillLateFee(id: $0.id, chargeId: $0.chargeId, chargeDueDate: $0.chargeDueDate, amount: $0.amount, amountPaid: $0.amountPaid, assessedAt: $0.assessedAt, waivedAt: $0.waivedAt) },
            termsSummary: DemoMath.billTermsSummary(
                amount: bill.amount,
                frequency: bill.frequency,
                lateFeeFlat: bill.lateFeeFlat,
                lateFeePercent: bill.lateFeePercent,
                graceDays: bill.lateFeeGraceDays,
                currency: data.currency
            )
        )
    }

    // MARK: - Errors

    static func notFound(_ subject: String) -> APIError {
        .problem(ProblemDetails(title: "Not found", status: 404, detail: "\(subject) not found.", errors: nil))
    }

    static func validation(_ message: String) -> APIError {
        .problem(ProblemDetails(title: "Invalid request", status: 400, detail: message, errors: nil))
    }
}
