import XCTest
@testable import BankOfDad

final class UtilityTests: XCTestCase {
    func testCalendarDateCodableAndComparable() throws {
        let first = try CalendarDate(string: "2026-09-27")
        let second = try CalendarDate(string: "2026-09-28")
        XCTAssertLessThan(first, second)
        let data = try JSONEncoder().encode(first)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-09-27\"")
        XCTAssertEqual(try JSONDecoder().decode(CalendarDate.self, from: data), first)
    }

    func testPairingCodeNormalization() {
        XCTAssertEqual(PairingCode.normalized(" k7q-4mz 2p "), "K7Q4MZ2P")
        XCTAssertEqual(PairingCode.display("k7q4mz2p"), "K7Q-4MZ-2P")
    }

    func testMoneyFormattingProducesCurrencyText() {
        let formatted = AppFormatters.money(Decimal(string: "12.34")!, currencyCode: "USD")
        XCTAssertFalse(formatted.isEmpty)
        XCTAssertTrue(formatted.contains("12"))
    }
}
