import XCTest

/// Shared base for the end-to-end suite: launches the app with the UI-test hooks and exposes
/// the seeding API plus small element helpers.
class BankUITestCase: XCTestCase {
    let api = TestAPI()
    private(set) var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let health = try? api.send("GET", "/health")
        guard health.map({ String(decoding: $0, as: UTF8.self) }) == "Healthy" else {
            throw XCTSkip("Backend is not reachable at \(TestAPI.baseURL). Run ios/scripts/run-ui-tests.sh.")
        }
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    /// Launches signed out (keychain cleared), or signed in with the given seeded session.
    @discardableResult
    func launch(as session: AuthTokens? = nil, resetKeychain: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITests"]
        if resetKeychain { app.launchArguments.append("-UITestsResetKeychain") }
        if let session {
            app.launchEnvironment["UITESTS_ACCESS_TOKEN"] = session.accessToken
            app.launchEnvironment["UITESTS_REFRESH_TOKEN"] = session.refreshToken
        }
        app.launch()
        self.app = app
        return app
    }

    @discardableResult
    func launch(as parent: Parent) -> XCUIApplication {
        let app = launch(as: parent.auth)
        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15), "Parent tabs did not appear")
        return app
    }

    // MARK: - Element lookup

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func button(_ identifierOrLabel: String) -> XCUIElement { app.buttons[identifierOrLabel].firstMatch }
    func text(_ label: String) -> XCUIElement { app.staticTexts[label].firstMatch }

    func textContaining(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    func anyContaining(_ fragment: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        dismissKeyboard()
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Tab \(name) missing", file: file, line: line)
        // Taps that land while the tab bar is still animating in are dropped, so confirm the selection.
        for _ in 0..<5 where !tab.isSelected {
            tab.tap()
            if tab.isSelected { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(tab.isSelected, "Could not select tab \(name)", file: file, line: line)
    }

    /// While a text field is being edited the tab bar is hidden (and the keyboard isn't always in the
    /// hierarchy), so end editing by submitting the focused field.
    func dismissKeyboard() {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch
        guard focused.exists else { return }
        focused.typeText("\n")
        _ = focused.waitForNonExistence(timeout: 3)
    }

    /// Picks an option from a SwiftUI menu-style Picker.
    func choose(_ option: String, in picker: XCUIElement) {
        picker.waitToAppear().tap()
        let item = app.buttons[option].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Picker option \(option) missing")
        item.tap()
    }

    func assertNoErrorBanner(file: StaticString = #filePath, line: UInt = #line) {
        let banner = element("errorBanner")
        XCTAssertFalse(banner.waitForExistence(timeout: 1.5), "Unexpected error banner: \(banner.exists ? banner.label : "")", file: file, line: line)
    }

    /// Drags the frontmost content (a sheet if one is up) until the element is fully visible
    /// between the navigation bar and the keyboard / tab bar.
    @discardableResult
    func scrollTo(_ element: XCUIElement, up: Bool = true, maxSwipes: Int = 10) -> XCUIElement {
        func isVisible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let screen = app.frame
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY : screen.maxY - 90
            return element.frame.minY >= screen.minY + 120 && element.frame.maxY <= bottom
        }
        var swipes = 0
        while !isVisible() && swipes < maxSwipes {
            // Stay in the upper half so the drag never starts on the keyboard.
            let (from, to): (CGFloat, CGFloat) = up ? (0.55, 0.25) : (0.3, 0.5)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
            swipes += 1
        }
        return element
    }

    /// Taps a Stepper's increment/decrement button `times` times.
    func step(_ stepper: XCUIElement, by delta: Int) {
        let suffix = delta > 0 ? "Increment" : "Decrement"
        let button = stepper.waitToAppear().buttons.matching(NSPredicate(format: "identifier ENDSWITH %@ OR label ENDSWITH %@", suffix, suffix)).firstMatch
        for _ in 0..<abs(delta) { button.tap() }
    }

    /// Polls a backend condition (the UI returns before its network call finishes).
    func eventually(_ description: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line, _ condition: () throws -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if (try? condition()) == true { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        } while Date() < deadline
        XCTFail("Timed out waiting for: \(description)", file: file, line: line)
    }
}

extension XCUIElement {
    @discardableResult
    func waitToAppear(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(waitForExistence(timeout: timeout), "Element did not appear: \(self)", file: file, line: line)
        return self
    }

    func waitToDisappear(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Element did not disappear: \(self)", file: file, line: line)
    }

    func waitFor(label fragment: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", fragment)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Label never contained '\(fragment)'; was '\(exists ? label : "<missing>")'", file: file, line: line)
    }

    func waitFor(value expected: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "Value never became '\(expected)'; was '\(exists ? String(describing: value) : "<missing>")'", file: file, line: line)
    }

    var stringValue: String { (value as? String) ?? "" }

    /// Taps the field, clears any existing text and types the new text.
    func replaceText(_ text: String) {
        waitToAppear().tap()
        let existing = stringValue
        if !existing.isEmpty, existing != placeholderValue {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        typeText(text)
    }

    var isOn: Bool { stringValue == "1" }

    /// SwiftUI toggles in a Form report their switch value via the element value ("0"/"1").
    func setSwitch(_ on: Bool) {
        waitToAppear()
        guard isOn != on else { return }
        let control = switches.firstMatch.exists ? switches.firstMatch : self
        control.tap()
        if isOn != on { coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
    }
}

enum Fmt {
    static func money(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: value as NSDecimalNumber)!
    }

    static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func date(day: String) -> String { date(TestAPI.date(day)) }
}

extension String {
    /// Loan/child ids are lowercase in JSON, but the app builds identifiers from `UUID.uuidString`.
    var uiID: String { uppercased() }
}
