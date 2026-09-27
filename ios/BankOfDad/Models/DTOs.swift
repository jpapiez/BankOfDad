import Foundation

struct UserDto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let familyId: UUID
    let role: Role
    let displayName: String
    let email: String?
}

struct FamilyDto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var timeZone: String
    var currency: String
    var parents: [UserDto]
    var children: [ChildDto]
}

struct ChildDto: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var displayName: String
    var avatarColor: String?
    var pairedDeviceCount: Int
}

struct LoanTermsInput: Codable, Hashable, Sendable {
    var childId: UUID
    var title: String
    var principal: Decimal
    var interestEnabled: Bool
    var annualRate: Decimal
    var frequency: Frequency
    var installmentCount: Int
    var firstDueDate: CalendarDate
    var lateFeeFlat: Decimal?
    var lateFeePercent: Decimal?
    var lateFeeGraceDays: Int
    var sendReminders: Bool
    var sendReceipts: Bool
}

struct SchedulePreview: Codable, Hashable, Sendable {
    let installmentAmount: Decimal
    let totalInterest: Decimal
    let totalRepayable: Decimal
    let installments: [SchedulePreviewItem]
}

struct SchedulePreviewItem: Codable, Identifiable, Hashable, Sendable {
    var id: Int { seq }
    let seq: Int
    let dueDate: CalendarDate
    let principalDue: Decimal
    let interestDue: Decimal
    let amountDue: Decimal
}

struct LoanSummary: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let childId: UUID
    let childName: String
    let principal: Decimal
    let status: LoanStatus
    let balance: Decimal
    let amountPaid: Decimal
    let nextDueDate: CalendarDate?
    let nextAmountDue: Decimal?
    let lateInstallments: Int
    let createdAt: Date
}

struct LoanDetail: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    let childId: UUID
    let childName: String
    let principal: Decimal
    var status: LoanStatus
    var balance: Decimal
    var amountPaid: Decimal
    var nextDueDate: CalendarDate?
    var nextAmountDue: Decimal?
    var lateInstallments: Int
    let createdAt: Date
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
    let totalInterest: Decimal
    let totalRepayable: Decimal
    var outstandingFees: Decimal
    var installments: [Installment]
    var payments: [Payment]
    var lateFees: [LateFee]
    let termsSummary: String
}

struct Installment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let seq: Int
    var dueDate: CalendarDate
    let principalDue: Decimal
    let interestDue: Decimal
    let amountDue: Decimal
    let principalPaid: Decimal
    let interestPaid: Decimal
    var remaining: Decimal
    var status: InstallmentStatus
}

struct LateFee: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let installmentId: UUID
    let installmentSeq: Int
    let amount: Decimal
    let amountPaid: Decimal
    let assessedAt: Date
    let waivedAt: Date?
}

struct Payment: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let amount: Decimal
    let paidOn: CalendarDate
    let note: String?
    let recordedByName: String
    let createdAt: Date
    let allocations: [Allocation]
}

struct Allocation: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(target.rawValue)-\(installmentSeq ?? -1)-\(lateFeeId?.uuidString ?? "none")-\(amount)" }
    let target: AllocationTarget
    let installmentSeq: Int?
    let lateFeeId: UUID?
    let amount: Decimal
}

struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let type: NotificationType
    let title: String
    let body: String
    let loanId: UUID?
    let createdAt: Date
    var readAt: Date?
}

struct Dashboard: Codable, Hashable, Sendable {
    let totalOutstanding: Decimal
    let activeLoans: Int
    let lateInstallments: Int
    let upcoming: [UpcomingItem]
}

struct UpcomingItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(loanId)-\(dueDate)" }
    let loanId: UUID
    let loanTitle: String
    let childName: String
    let dueDate: CalendarDate
    let amountDue: Decimal
}

struct AuthResponse: Codable, Hashable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: UserDto
}

struct PairingCodeResponse: Codable, Hashable, Sendable {
    let code: String
    let qrPayload: String
    let expiresAt: Date
}

extension PairingCodeResponse: Identifiable {
    var id: String { code }
}

struct InviteResponse: Codable, Hashable, Sendable {
    let inviteCode: String
    let expiresAt: Date
}
