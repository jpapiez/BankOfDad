import XCTest

/// Demo mode runs entirely on-device, so these tests never need the backend. They deliberately do
/// not inherit from `BankUITestCase`, which skips whenever the API is unreachable.
final class DemoModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDown() {
        app?.terminate()
        super.tearDown()
    }

    @discardableResult
    private func launch(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITests", "-UITestsResetKeychain"] + extraArguments
        app.launch()
        self.app = app
        return app
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The banner lives in a safe-area inset above the tab content.
    private func openDemoOptions(file: StaticString = #filePath, line: UInt = #line) {
        let banner = app.buttons["demo.banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "Demo banner missing", file: file, line: line)
        if banner.isHittable {
            banner.tap()
        } else {
            // The banner sits under the status bar, so aim at its lower half.
            banner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        }
        XCTAssertTrue(app.navigationBars["Demo options"].waitForExistence(timeout: 10), "Demo options sheet did not open", file: file, line: line)
    }

    private func textContaining(_ fragment: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", fragment)).firstMatch
    }

    private func waitForTab(_ name: String, timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.buttons[name].waitForExistence(timeout: timeout), "Tab \(name) never appeared", file: file, line: line)
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 20), "Tab \(name) missing")
        for _ in 0..<5 where !tab.isSelected {
            tab.tap()
            if tab.isSelected { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTAssertTrue(tab.isSelected, "Could not select tab \(name)")
    }

    // MARK: - Entry

    func testWelcomeOffersTheDemoAndParentDemoLoads() {
        launch()
        let entry = app.buttons["welcome.demo"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20), "Welcome should offer Explore Demo")
        entry.tap()

        let parentStart = app.buttons["demo.start.parent"]
        XCTAssertTrue(parentStart.waitForExistence(timeout: 10))
        parentStart.tap()

        waitForTab("Dashboard")
        XCTAssertTrue(element("demo.banner").waitForExistence(timeout: 10), "The demo banner must stay visible")
        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 10), "Seeded loans should be on screen")
    }

    func testDemoBannerIsPresentOnEveryParentTab() {
        launch(["-DemoMode"])
        waitForTab("Dashboard")
        for tab in ["Dashboard", "Owed", "Family", "Settings"] {
            openTab(tab)
            XCTAssertTrue(element("demo.banner").waitForExistence(timeout: 5), "Demo banner missing on \(tab)")
        }
    }

    func testSeededStoryIsVisibleToTheParent() {
        launch(["-DemoMode"])
        waitForTab("Dashboard")
        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 15))

        openTab("Owed")
        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 10))
        XCTAssertTrue(textContaining("Skateboard upgrade").waitForExistence(timeout: 10))
        XCTAssertTrue(textContaining("Car insurance").waitForExistence(timeout: 10))

        openTab("Family")
        XCTAssertTrue(textContaining("Maya").waitForExistence(timeout: 10))
        XCTAssertTrue(textContaining("Theo").waitForExistence(timeout: 10))
    }

    func testKidDemoLaunchesStraightIntoTheKidExperience() {
        launch(["-DemoMode", "-DemoRole", "kid"])
        XCTAssertTrue(element("demo.banner").waitForExistence(timeout: 20))
        waitForTab("Inbox")
        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 15), "The kid should see their own loan")
    }

    // MARK: - Controls

    func testSwitchingRolesFromTheBanner() {
        launch(["-DemoMode"])
        waitForTab("Dashboard")

        openDemoOptions()
        let kidSwitch = app.buttons["demo.switch.child.Theo"]
        XCTAssertTrue(kidSwitch.waitForExistence(timeout: 10))
        kidSwitch.tap()

        waitForTab("Inbox")
        XCTAssertTrue(textContaining("Skateboard upgrade").waitForExistence(timeout: 15), "Theo's loan should be visible")

        openDemoOptions()
        let parentSwitch = app.buttons["demo.switch.parent"]
        XCTAssertTrue(parentSwitch.waitForExistence(timeout: 10))
        parentSwitch.tap()
        waitForTab("Dashboard")
    }

    func testResetRestoresTheSampleData() {
        launch(["-DemoMode"])
        waitForTab("Owed")
        openTab("Owed")
        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 15))

        openDemoOptions()
        let reset = app.buttons["demo.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
        let confirm = app.buttons["Reset demo data"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()

        XCTAssertTrue(textContaining("Mountain bike").waitForExistence(timeout: 15), "The seed should be back")
    }

    func testExitingTheDemoReturnsToWelcome() {
        launch(["-DemoMode"])
        waitForTab("Dashboard")

        openDemoOptions()
        let exit = app.buttons["demo.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10))
        exit.tap()

        XCTAssertTrue(app.buttons["welcome.demo"].waitForExistence(timeout: 15), "Exiting should land back on Welcome")
        XCTAssertFalse(element("demo.banner").exists, "The banner must disappear when the demo ends")
    }

    func testExitFromSettingsEndsTheDemo() {
        launch(["-DemoMode"])
        waitForTab("Settings")
        openTab("Settings")

        let exit = app.buttons["settings.exitDemo"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10), "Settings should offer an exit in demo mode")
        XCTAssertFalse(app.buttons["settings.signOut"].exists, "Demo mode must not offer a real sign out")
        exit.tap()
        XCTAssertTrue(app.buttons["welcome.demo"].waitForExistence(timeout: 15))
    }

    // MARK: - Determinism

    func testFixedDateProducesTheSameScreenshotContent() {
        launch(["-DemoMode", "-DemoDate", "2025-06-15"])
        waitForTab("Owed")
        openTab("Owed")
        let first = app.staticTexts.allElementsBoundByIndex.map(\.label)
        app.terminate()

        launch(["-DemoMode", "-DemoDate", "2025-06-15"])
        waitForTab("Owed")
        openTab("Owed")
        let second = app.staticTexts.allElementsBoundByIndex.map(\.label)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second, "A fixed demo date must render identical content for screenshots")
    }

    // MARK: - Accessibility

    func testDemoControlsAreLabelledForVoiceOver() {
        launch(["-DemoMode"])
        let banner = app.buttons["demo.banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 20))
        XCTAssertTrue(banner.label.contains("Demo mode"), "Banner label was '\(banner.label)'")

        openDemoOptions()
        for identifier in ["demo.switch.parent", "demo.switch.child.Maya", "demo.reset", "demo.exit"] {
            let control = app.buttons[identifier].firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 10), "\(identifier) missing")
            XCTAssertFalse(control.label.isEmpty, "\(identifier) has no accessibility label")
        }
    }
}
