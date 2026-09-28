import Foundation

enum AppFormatters {
    static func money(_ value: Decimal, currencyCode: String = "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = Locale.current
        return formatter.string(from: value as NSDecimalNumber) ?? "\(currencyCode) \(value)"
    }

    static func percent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)%"
    }

    static func date(_ value: CalendarDate) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value.date())
    }

    static func timestamp(_ value: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: value, relativeTo: Date())
    }
}
