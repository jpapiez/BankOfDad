import Foundation

enum FormValues {
    static func decimal(_ text: String) -> Decimal {
        let normalized = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Decimal(Double(normalized) ?? 0)
    }

    static func percentFraction(_ text: String) -> Decimal {
        var value = FormValues.decimal(text)
        var divisor = Decimal(100)
        var result = Decimal()
        NSDecimalDivide(&result, &value, &divisor, .plain)
        return result
    }
}
