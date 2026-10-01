import Foundation

/// Swift port of the server-side loan/bill math (`BankOfDad.Domain.Services`).
///
/// Demo mode recomputes schedules, due statuses, late fees and payment allocations locally so the
/// numbers a reviewer sees behave exactly like the real product — balances fall when a payment is
/// recorded, late fees appear on overdue installments, and a fully-paid loan flips to "Paid off".
enum DemoMath {
    // MARK: - Money

    static func round(_ value: Decimal) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    // MARK: - Calendar

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func periodsPerYear(_ frequency: Frequency) -> Int {
        switch frequency {
        case .weekly: return 52
        case .biweekly: return 26
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        case .unknown: return 12
        }
    }

    /// Offsets are always computed from the first due date so month-end dates clamp the same way the
    /// server does (Jan 31 -> Feb 28), instead of drifting as each period is added.
    static func dueDate(first: CalendarDate, frequency: Frequency, seq: Int) -> CalendarDate {
        let steps = seq - 1
        guard steps > 0 else { return first }
        let calendar = calendar
        let start = first.date(in: calendar.timeZone)
        let component: Calendar.Component
        let value: Int
        switch frequency {
        case .weekly: component = .day; value = 7 * steps
        case .biweekly: component = .day; value = 14 * steps
        case .monthly: component = .month; value = steps
        case .quarterly: component = .month; value = 3 * steps
        case .yearly: component = .year; value = steps
        case .unknown: component = .month; value = steps
        }
        let shifted = calendar.date(byAdding: component, value: value, to: start) ?? start
        return CalendarDate(shifted, timeZone: calendar.timeZone)
    }

    static func daysBetween(_ from: CalendarDate, _ to: CalendarDate) -> Int {
        let calendar = calendar
        let components = calendar.dateComponents(
            [.day],
            from: from.date(in: calendar.timeZone),
            to: to.date(in: calendar.timeZone)
        )
        return components.day ?? 0
    }

    // MARK: - Schedule

    struct ScheduleRow: Sendable {
        let seq: Int
        let dueDate: CalendarDate
        let principalDue: Decimal
        let interestDue: Decimal
        var amountDue: Decimal { principalDue + interestDue }
    }

    static func schedule(
        principal: Decimal,
        annualRate: Decimal,
        interestEnabled: Bool,
        frequency: Frequency,
        installmentCount: Int,
        firstDueDate: CalendarDate
    ) -> [ScheduleRow] {
        guard installmentCount > 0, principal > 0 else { return [] }
        let periods = periodsPerYear(frequency)
        let rate = interestEnabled && annualRate > 0
            ? annualRate / Decimal(periods)
            : Decimal(0)

        var rows: [ScheduleRow] = []
        var balance = principal

        if rate == 0 {
            let flat = round(principal / Decimal(installmentCount))
            for seq in 1...installmentCount {
                let principalDue = seq == installmentCount ? balance : min(flat, balance)
                balance -= principalDue
                rows.append(ScheduleRow(seq: seq, dueDate: dueDate(first: firstDueDate, frequency: frequency, seq: seq), principalDue: round(principalDue), interestDue: 0))
            }
            return rows
        }

        let payment = round(annuityPayment(principal: principal, rate: rate, count: installmentCount))
        for seq in 1...installmentCount {
            let interestDue = round(balance * rate)
            var principalDue = payment - interestDue
            if seq == installmentCount || principalDue > balance { principalDue = balance }
            balance -= principalDue
            rows.append(ScheduleRow(seq: seq, dueDate: dueDate(first: firstDueDate, frequency: frequency, seq: seq), principalDue: round(principalDue), interestDue: interestDue))
        }
        return rows
    }

    private static func annuityPayment(principal: Decimal, rate: Decimal, count: Int) -> Decimal {
        let p = NSDecimalNumber(decimal: principal).doubleValue
        let r = NSDecimalNumber(decimal: rate).doubleValue
        let factor = pow(1 + r, Double(count))
        guard factor > 1 else { return principal / Decimal(count) }
        let payment = p * r * factor / (factor - 1)
        return Decimal(payment)
    }

    // MARK: - Status

    static func dueStatus(remaining: Decimal, dueDate: CalendarDate, today: CalendarDate, graceDays: Int) -> InstallmentStatus {
        if remaining <= 0 { return .paid }
        if today < dueDate { return .upcoming }
        if daysBetween(dueDate, today) <= max(0, graceDays) { return .due }
        return .late
    }

    /// Matches `DueStatus.LateFee`: the flat and percent components are additive, and the percent
    /// component applies to the *remaining* balance of the missed installment or charge.
    static func lateFeeAmount(flat: Decimal?, percent: Decimal?, base: Decimal) -> Decimal {
        round((flat ?? 0) + (percent ?? 0) * base)
    }

    // MARK: - Terms summaries

    static func loanTermsSummary(
        principal: Decimal,
        interestEnabled: Bool,
        annualRate: Decimal,
        frequency: Frequency,
        installmentCount: Int,
        installmentAmount: Decimal,
        lateFeeFlat: Decimal?,
        lateFeePercent: Decimal?,
        graceDays: Int,
        currency: String
    ) -> String {
        let cadence = cadenceWord(frequency)
        var text = "\(AppFormatters.money(principal, currencyCode: currency)) repaid over \(installmentCount) \(cadence) payment\(installmentCount == 1 ? "" : "s") of \(AppFormatters.money(installmentAmount, currencyCode: currency))"
        if interestEnabled && annualRate > 0 {
            text += " at \(AppFormatters.percent(annualRate)) APR"
        } else {
            text += " with no interest"
        }
        text += "."
        if let feeText = lateFeeSentence(flat: lateFeeFlat, percent: lateFeePercent, graceDays: graceDays, currency: currency) {
            text += " " + feeText
        }
        return text
    }

    static func billTermsSummary(
        amount: Decimal,
        frequency: Frequency,
        lateFeeFlat: Decimal?,
        lateFeePercent: Decimal?,
        graceDays: Int,
        currency: String
    ) -> String {
        var text = "\(AppFormatters.money(amount, currencyCode: currency)) due \(cadenceWord(frequency))."
        if let feeText = lateFeeSentence(flat: lateFeeFlat, percent: lateFeePercent, graceDays: graceDays, currency: currency) {
            text += " " + feeText
        }
        return text
    }

    private static func lateFeeSentence(flat: Decimal?, percent: Decimal?, graceDays: Int, currency: String) -> String? {
        var parts: [String] = []
        if let flat, flat > 0 { parts.append(AppFormatters.money(flat, currencyCode: currency)) }
        if let percent, percent > 0 { parts.append("\(AppFormatters.percent(percent)) of the missed payment") }
        guard !parts.isEmpty else { return nil }
        let fee = parts.joined(separator: " + ")
        if graceDays > 0 {
            return "Late fee of \(fee) after \(graceDays) grace day\(graceDays == 1 ? "" : "s")."
        }
        return "Late fee of \(fee) once a payment is overdue."
    }

    private static func cadenceWord(_ frequency: Frequency) -> String {
        switch frequency {
        case .weekly: return "weekly"
        case .biweekly: return "every two weeks"
        case .monthly: return "monthly"
        case .quarterly: return "quarterly"
        case .yearly: return "yearly"
        case .unknown: return "monthly"
        }
    }
}
