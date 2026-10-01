import Foundation

/// Launch arguments that start the app directly in demo mode.
///
/// Unlike `UITestHooks` these are honored in every configuration: screenshot automation runs against
/// Release builds, and demo mode is a shipping, user-facing feature rather than a test backdoor. They
/// only ever select demo content — they cannot touch real accounts or the production API.
///
/// ```
/// xcrun simctl launch <device> com.example.BankOfDad -DemoMode -DemoRole kid -DemoDate 2025-03-14
/// ```
struct DemoLaunchOptions: Equatable, Sendable {
    static let modeArgument = "-DemoMode"
    static let roleArgument = "-DemoRole"
    static let dateArgument = "-DemoDate"

    var isEnabled: Bool = false
    var role: Role = .parent
    /// Fixes the demo clock so screenshots are byte-for-byte repeatable.
    var referenceDate: Date?

    static var current: DemoLaunchOptions { parse(ProcessInfo.processInfo.arguments) }

    static func parse(_ arguments: [String]) -> DemoLaunchOptions {
        var options = DemoLaunchOptions()
        guard arguments.contains(modeArgument) else { return options }
        options.isEnabled = true
        if let index = arguments.firstIndex(of: roleArgument), index + 1 < arguments.count {
            let value = arguments[index + 1].lowercased()
            options.role = (value == "kid" || value == "child") ? .child : .parent
        }
        if let index = arguments.firstIndex(of: dateArgument), index + 1 < arguments.count,
           let parsed = try? CalendarDate(string: arguments[index + 1]) {
            options.referenceDate = parsed.date(in: DemoMath.calendar.timeZone)
        }
        return options
    }
}
