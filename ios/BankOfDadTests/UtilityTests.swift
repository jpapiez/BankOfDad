import SwiftUI
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

    func testAvatarPaletteMatchesStoredHexCaseInsensitively() {
        XCTAssertEqual(AvatarPalette.option(for: "#ff9f1c")?.name, "Orange")
        XCTAssertEqual(AvatarPalette.option(for: AvatarPalette.defaultHex)?.name, "Blue")
        XCTAssertNil(AvatarPalette.option(for: "#123456"), "Custom colors have no swatch")
        XCTAssertNil(AvatarPalette.option(for: nil))
        XCTAssertEqual(Set(AvatarPalette.options.map(\.hex)).count, AvatarPalette.options.count)
        XCTAssertTrue(AvatarPalette.options.allSatisfy { $0.hex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil }, "Hexes must pass the API's validation")
    }

    func testLightColorsGetDarkInitials() {
        let dark = AvatarPalette.options.filter { Color.isLight(hex: $0.hex) }.map(\.name)
        XCTAssertEqual(Set(dark), ["Orange", "Teal", "Yellow"])
        XCTAssertFalse(Color.isLight(hex: nil))
        XCTAssertFalse(Color.isLight(hex: "not a color"))
    }
}
