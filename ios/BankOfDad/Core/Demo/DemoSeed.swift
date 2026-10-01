import Foundation

/// Deterministic sample data for demo mode.
///
/// Everything is expressed relative to a reference date (normally "now"), so the demo always looks
/// freshly used: a loan that is partly repaid, one payment that slipped past its grace period and
/// collected a late fee, a loan that has been paid off, recurring bills with real charge history, and
/// an Inbox with reminders and receipts. Seeded payments are replayed through `DemoEngine` at their
/// historical dates so every balance, allocation and receipt is internally consistent.
enum DemoSeed {
    static let familyId = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let parentId = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let mayaId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let theoId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!

    static let inviteCode = "PARKER-FAMILY"

    static func pairingCode(for childId: UUID) -> String {
        switch childId {
        case mayaId: return "482913"
        case theoId: return "571064"
        default: return String(format: "%06d", abs(childId.hashValue % 1_000_000))
        }
    }

    static func make(referenceDate: Date = Date()) -> DemoData {
        let parent = UserDto(id: parentId, familyId: familyId, role: .parent, displayName: "Alex Parker", email: "alex@example.com")
        let children = [
            DemoChild(id: mayaId, displayName: "Maya", avatarColor: "#4F8EF7", pairedDeviceCount: 1),
            DemoChild(id: theoId, displayName: "Theo", avatarColor: "#FF9F1C", pairedDeviceCount: 1)
        ]

        var data = DemoData(
            familyId: familyId,
            familyName: "The Parkers",
            timeZone: TimeZone.current.identifier,
            currency: "USD",
            parent: parent,
            children: children,
            loans: [],
            bills: [],
            notifications: []
        )

        // MARK: Loans

        let bike = loan(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555501")!,
            childId: mayaId,
            title: "Mountain bike",
            principal: 480,
            interestEnabled: true,
            annualRate: Decimal(string: "0.05")!,
            frequency: .monthly,
            count: 6,
            firstDue: day(referenceDate, offset: -72),
            createdAt: date(referenceDate, offset: -80),
            lateFeeFlat: 5,
            graceDays: 3
        )
        let tickets = loan(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555502")!,
            childId: theoId,
            title: "Concert tickets",
            principal: 180,
            interestEnabled: false,
            annualRate: 0,
            frequency: .monthly,
            count: 3,
            firstDue: day(referenceDate, offset: -100),
            createdAt: date(referenceDate, offset: -108),
            lateFeeFlat: 5,
            graceDays: 3
        )
        let skateboard = loan(
            id: UUID(uuidString: "55555555-5555-4555-8555-555555555503")!,
            childId: theoId,
            title: "Skateboard upgrade",
            principal: 240,
            interestEnabled: false,
            annualRate: 0,
            frequency: .biweekly,
            count: 6,
            firstDue: day(referenceDate, offset: -11),
            createdAt: date(referenceDate, offset: -18),
            lateFeeFlat: 5,
            graceDays: 3
        )
        data.loans = [bike, tickets, skateboard]

        // MARK: Bills

        data.bills = [
            bill(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666601")!,
                childId: mayaId,
                title: "Car insurance",
                amount: 120,
                frequency: .monthly,
                firstDue: day(referenceDate, offset: -45),
                createdAt: date(referenceDate, offset: -52)
            ),
            bill(
                id: UUID(uuidString: "66666666-6666-4666-8666-666666666602")!,
                childId: theoId,
                title: "Phone plan",
                amount: 25,
                frequency: .monthly,
                firstDue: day(referenceDate, offset: 4),
                createdAt: date(referenceDate, offset: -6)
            )
        ]

        // MARK: Announcements that predate the payment history

        data.notifications = [
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777701")!, childId: mayaId, type: .loanCreated, title: "New loan: Mountain bike", body: "$480.00 over 6 monthly payments.", loanId: bike.id, billId: nil, createdAt: date(referenceDate, offset: -80), readAt: date(referenceDate, offset: -79)),
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777702")!, childId: theoId, type: .loanCreated, title: "New loan: Skateboard upgrade", body: "$240.00 over 6 payments every two weeks.", loanId: skateboard.id, billId: nil, createdAt: date(referenceDate, offset: -18), readAt: date(referenceDate, offset: -17)),
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777703")!, childId: mayaId, type: .billCreated, title: "New bill: Car insurance", body: "$120.00 monthly.", loanId: nil, billId: data.bills[0].id, createdAt: date(referenceDate, offset: -52), readAt: date(referenceDate, offset: -51)),
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777704")!, childId: theoId, type: .billCreated, title: "New bill: Phone plan", body: "$25.00 monthly.", loanId: nil, billId: data.bills[1].id, createdAt: date(referenceDate, offset: -6), readAt: nil),
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777705")!, childId: mayaId, type: .reminder, title: "Payment due soon", body: "Mountain bike payment is coming up.", loanId: bike.id, billId: nil, createdAt: date(referenceDate, offset: -44), readAt: date(referenceDate, offset: -44)),
            DemoNotification(id: UUID(uuidString: "77777777-7777-4777-8777-777777777706")!, childId: theoId, type: .reminder, title: "Payment due soon", body: "Skateboard upgrade payment is due in 3 days.", loanId: skateboard.id, billId: nil, createdAt: date(referenceDate, offset: -3), readAt: nil)
        ]

        // MARK: Replay the payment history
        //
        // Steps are applied in chronological order: `DemoEngine` accrues late fees up to its own
        // `now`, so replaying out of order would assess fees for payments that had not happened yet.

        let bikeInstallment = bike.installments.first?.amountDue ?? 0
        let insuranceId = data.bills[0].id
        var steps: [(offset: Int, apply: (inout DemoEngine) throws -> Void)] = [
            (-71, { try $0.recordLoanPayment(loanId: bike.id, amount: bikeInstallment, paidOn: day(referenceDate, offset: -71), note: "Birthday money") }),
            (-36, { try $0.recordLoanPayment(loanId: bike.id, amount: bikeInstallment + 5, paidOn: day(referenceDate, offset: -36), note: "Catching up after a late week") }),
            (-99, { try $0.recordLoanPayment(loanId: tickets.id, amount: 60, paidOn: day(referenceDate, offset: -99), note: nil) }),
            (-69, { try $0.recordLoanPayment(loanId: tickets.id, amount: 60, paidOn: day(referenceDate, offset: -69), note: nil) }),
            (-39, { try $0.recordLoanPayment(loanId: tickets.id, amount: 60, paidOn: day(referenceDate, offset: -39), note: "All paid off!") }),
            (-10, { try $0.recordLoanPayment(loanId: skateboard.id, amount: 40, paidOn: day(referenceDate, offset: -10), note: nil) }),
            (-44, { try $0.recordBillPayment(billId: insuranceId, amount: 120, paidOn: day(referenceDate, offset: -44), note: nil) }),
            (-14, { try $0.recordBillPayment(billId: insuranceId, amount: 120, paidOn: day(referenceDate, offset: -14), note: nil) })
        ]
        steps.sort { $0.offset < $1.offset }
        for step in steps {
            apply(&data, at: date(referenceDate, offset: step.offset), step.apply)
        }

        // Bring everything up to today: generate due charges and assess the overdue bike payment.
        var engine = DemoEngine(data: data, now: referenceDate)
        _ = engine.dashboard()
        return engine.data
    }

    // MARK: - Builders

    private static func apply(_ data: inout DemoData, at moment: Date, _ body: (inout DemoEngine) throws -> Void) {
        var engine = DemoEngine(data: data, now: moment)
        do {
            try body(&engine)
            data = engine.data
        } catch {
            assertionFailure("Demo seed step failed: \(error)")
        }
    }

    private static func loan(
        id: UUID,
        childId: UUID,
        title: String,
        principal: Decimal,
        interestEnabled: Bool,
        annualRate: Decimal,
        frequency: Frequency,
        count: Int,
        firstDue: CalendarDate,
        createdAt: Date,
        lateFeeFlat: Decimal?,
        graceDays: Int
    ) -> DemoLoan {
        let rows = DemoMath.schedule(principal: principal, annualRate: annualRate, interestEnabled: interestEnabled, frequency: frequency, installmentCount: count, firstDueDate: firstDue)
        return DemoLoan(
            id: id,
            childId: childId,
            title: title,
            principal: principal,
            interestEnabled: interestEnabled,
            annualRate: annualRate,
            frequency: frequency,
            installmentCount: count,
            firstDueDate: firstDue,
            lateFeeFlat: lateFeeFlat,
            lateFeePercent: nil,
            lateFeeGraceDays: graceDays,
            sendReminders: true,
            sendReceipts: true,
            status: .active,
            createdAt: createdAt,
            installments: rows.map { DemoInstallment(id: installmentId(loanId: id, seq: $0.seq), seq: $0.seq, dueDate: $0.dueDate, principalDue: $0.principalDue, interestDue: $0.interestDue) }
        )
    }

    private static func bill(
        id: UUID,
        childId: UUID,
        title: String,
        amount: Decimal,
        frequency: Frequency,
        firstDue: CalendarDate,
        createdAt: Date
    ) -> DemoBill {
        DemoBill(
            id: id,
            childId: childId,
            title: title,
            amount: amount,
            frequency: frequency,
            firstDueDate: firstDue,
            lateFeeFlat: 5,
            lateFeePercent: nil,
            lateFeeGraceDays: 3,
            sendReminders: true,
            sendReceipts: true,
            status: .active,
            createdAt: createdAt,
            endedAt: nil
        )
    }

    /// Stable per-installment identifiers keep SwiftUI diffs and UI tests predictable across resets.
    private static func installmentId(loanId: UUID, seq: Int) -> UUID {
        var bytes = loanId.uuid
        bytes.15 = UInt8(seq & 0xFF)
        return UUID(uuid: bytes)
    }

    // MARK: - Relative dates

    private static func date(_ reference: Date, offset: Int) -> Date {
        DemoMath.calendar.date(byAdding: .day, value: offset, to: reference) ?? reference
    }

    private static func day(_ reference: Date, offset: Int) -> CalendarDate {
        CalendarDate(date(reference, offset: offset), timeZone: DemoMath.calendar.timeZone)
    }
}
