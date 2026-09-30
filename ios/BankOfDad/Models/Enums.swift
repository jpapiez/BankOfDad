import Foundation

protocol UnknownFallbackCodable: RawRepresentable, Codable where RawValue == String {
    static var unknown: Self { get }
}

extension UnknownFallbackCodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum Role: String, CaseIterable, UnknownFallbackCodable, Sendable { case parent, child, unknown }
enum Frequency: String, CaseIterable, UnknownFallbackCodable, Sendable { case weekly, biweekly, monthly, quarterly, yearly, unknown }
enum LoanStatus: String, CaseIterable, UnknownFallbackCodable, Sendable { case active, paidOff, cancelled, unknown }
enum BillStatus: String, CaseIterable, UnknownFallbackCodable, Sendable { case active, ended, unknown }
enum InstallmentStatus: String, CaseIterable, UnknownFallbackCodable, Sendable { case upcoming, due, late, paid, unknown }
enum NotificationType: String, CaseIterable, UnknownFallbackCodable, Sendable { case reminder, receipt, loanCreated, lateFee, billCreated, unknown }
enum AllocationTarget: String, CaseIterable, UnknownFallbackCodable, Sendable { case lateFee, interest, principal, charge, unknown }

extension Frequency {
    static var selectable: [Frequency] { [.weekly, .biweekly, .monthly] }
    static var billSelectable: [Frequency] { [.weekly, .biweekly, .monthly, .quarterly, .yearly] }
    var label: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every two weeks"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        case .unknown: return "Unknown"
        }
    }
}

extension BillStatus {
    var label: String {
        switch self {
        case .active: return "Active"
        case .ended: return "Ended"
        case .unknown: return "Unknown"
        }
    }
}

extension LoanStatus {
    var label: String {
        switch self {
        case .active: return "Active"
        case .paidOff: return "Paid off"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }
}

extension InstallmentStatus {
    var label: String {
        switch self {
        case .upcoming: return "Upcoming"
        case .due: return "Due"
        case .late: return "Late"
        case .paid: return "Paid"
        case .unknown: return "Unknown"
        }
    }
}
