import Foundation

/// Mutable in-memory records backing demo mode. They mirror the server entities closely enough that
/// `DemoStore` can project them into the same DTOs the live API returns.

struct DemoChild: Sendable {
    let id: UUID
    var displayName: String
    var avatarColor: String?
    var pairedDeviceCount: Int
}

struct DemoInstallment: Sendable {
    let id: UUID
    let seq: Int
    var dueDate: CalendarDate
    let principalDue: Decimal
    let interestDue: Decimal
    var principalPaid: Decimal = 0
    var interestPaid: Decimal = 0

    var amountDue: Decimal { principalDue + interestDue }
    var remaining: Decimal { max(0, amountDue - principalPaid - interestPaid) }
}

struct DemoLateFee: Sendable {
    let id: UUID
    let installmentId: UUID
    let installmentSeq: Int
    let amount: Decimal
    var amountPaid: Decimal = 0
    let assessedAt: Date
    var waivedAt: Date?

    var remaining: Decimal { waivedAt == nil ? max(0, amount - amountPaid) : 0 }
}

struct DemoPayment: Sendable {
    let id: UUID
    let amount: Decimal
    let paidOn: CalendarDate
    let note: String?
    let recordedByName: String
    let createdAt: Date
    var allocations: [Allocation]
}

struct DemoLoan: Sendable {
    let id: UUID
    let childId: UUID
    var title: String
    let principal: Decimal
    let interestEnabled: Bool
    let annualRate: Decimal
    let frequency: Frequency
    let installmentCount: Int
    let firstDueDate: CalendarDate
    let lateFeeFlat: Decimal?
    let lateFeePercent: Decimal?
    let lateFeeGraceDays: Int
    var sendReminders: Bool
    var sendReceipts: Bool
    var status: LoanStatus
    let createdAt: Date
    var installments: [DemoInstallment]
    var lateFees: [DemoLateFee] = []
    var payments: [DemoPayment] = []

    var totalInterest: Decimal { installments.reduce(0) { $0 + $1.interestDue } }
    var totalRepayable: Decimal { installments.reduce(0) { $0 + $1.amountDue } }
    var outstandingFees: Decimal { lateFees.reduce(0) { $0 + $1.remaining } }
    var amountPaid: Decimal { payments.reduce(0) { $0 + $1.amount } }
    var balance: Decimal {
        guard status == .active else { return 0 }
        return installments.reduce(0) { $0 + $1.remaining } + outstandingFees
    }
}

struct DemoBillCharge: Sendable {
    let id: UUID
    let seq: Int
    let dueDate: CalendarDate
    var amount: Decimal
    var amountPaid: Decimal = 0
    var closed: Bool = false

    var remaining: Decimal { closed ? 0 : max(0, amount - amountPaid) }
}

struct DemoBillLateFee: Sendable {
    let id: UUID
    let chargeId: UUID
    let chargeDueDate: CalendarDate
    let amount: Decimal
    var amountPaid: Decimal = 0
    let assessedAt: Date
    var waivedAt: Date?

    var remaining: Decimal { waivedAt == nil ? max(0, amount - amountPaid) : 0 }
}

struct DemoBillPayment: Sendable {
    let id: UUID
    let amount: Decimal
    let paidOn: CalendarDate
    let note: String?
    let recordedByName: String
    let createdAt: Date
    var allocations: [BillAllocation]
}

struct DemoBill: Sendable {
    let id: UUID
    let childId: UUID
    var title: String
    var amount: Decimal
    let frequency: Frequency
    let firstDueDate: CalendarDate
    let lateFeeFlat: Decimal?
    let lateFeePercent: Decimal?
    let lateFeeGraceDays: Int
    var sendReminders: Bool
    var sendReceipts: Bool
    var status: BillStatus
    let createdAt: Date
    var endedAt: Date?
    var charges: [DemoBillCharge] = []
    var lateFees: [DemoBillLateFee] = []
    var payments: [DemoBillPayment] = []

    var outstandingFees: Decimal { lateFees.reduce(0) { $0 + $1.remaining } }
    var amountPaid: Decimal { payments.reduce(0) { $0 + $1.amount } }
}

struct DemoNotification: Sendable {
    let id: UUID
    let childId: UUID
    let type: NotificationType
    let title: String
    let body: String
    let loanId: UUID?
    let billId: UUID?
    let createdAt: Date
    var readAt: Date?
}

/// Everything demo mode knows about the sample family. `DemoStore` keeps one of these and swaps in a
/// freshly seeded copy when the user taps "Reset demo data".
struct DemoData: Sendable {
    var familyId: UUID
    var familyName: String
    var timeZone: String
    var currency: String
    var parent: UserDto
    var children: [DemoChild]
    var loans: [DemoLoan]
    var bills: [DemoBill]
    var notifications: [DemoNotification]
}
