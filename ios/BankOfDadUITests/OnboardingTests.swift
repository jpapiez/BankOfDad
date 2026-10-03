import XCTest

final class OnboardingTests: BankUITestCase {
    func testWelcomeOffersBankAndKidEntryPoints() {
        launch()
        XCTAssertTrue(element("welcome.parent").waitForExistence(timeout: 15))
        XCTAssertTrue(element("welcome.kid").exists)
        XCTAssertTrue(text("Bank of Dad").exists)
    }

    func testParentCreatesAccountThroughTheForm() throws {
        launch()
        element("welcome.parent").waitToAppear(timeout: 15).tap()
        element("signIn.toggleRegister").waitToAppear().tap()

        let email = TestAPI.uniqueEmail("register")
        element("signIn.email").replaceText(email)
        element("signIn.password").replaceText("short7!")
        element("signIn.displayName").replaceText("Pat")
        element("signIn.familyName").replaceText("The Registers")
        let submit = element("signIn.submit")
        XCTAssertEqual(submit.label, "Create bank")
        XCTAssertFalse(submit.isEnabled, "Passwords under 8 characters must not be submittable")

        element("signIn.password").replaceText(TestAPI.password)
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
        openTab("Settings")
        element("settings.email").waitFor(label: email)
        element("settings.name").waitFor(label: "Pat")
        XCTAssertNoThrow(try api.login(email: email, password: TestAPI.password))
    }

    func testParentSignsInWithEmailAndPassword() throws {
        let parent = try api.registerParent(name: "Sign In Dad")
        launch()
        element("welcome.parent").waitToAppear(timeout: 15).tap()
        XCTAssertEqual(element("signIn.submit").waitToAppear().label, "Sign in")
        element("signIn.email").replaceText(parent.email)
        element("signIn.password").replaceText(parent.password)
        element("signIn.submit").tap()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
        openTab("Settings")
        element("settings.name").waitFor(label: "Sign In Dad")
        element("settings.role").waitFor(label: "parent")
    }

    func testBadCredentialsShowAnErrorBanner() throws {
        let parent = try api.registerParent()
        launch()
        element("welcome.parent").waitToAppear(timeout: 15).tap()
        element("signIn.email").replaceText(parent.email)
        element("signIn.password").replaceText("WrongPassword1")
        element("signIn.submit").tap()

        element("errorBanner").waitToAppear().waitFor(label: "Error")
        XCTAssertFalse(app.tabBars.buttons["Dashboard"].exists)
        XCTAssertTrue(element("signIn.submit").exists, "Still on the sign-in form")
    }

    func testSignInWithAppleIsHiddenWhenServerDoesNotAdvertiseIt() {
        launch()
        element("welcome.parent").waitToAppear(timeout: 15).tap()
        XCTAssertTrue(element("signIn.email").waitForExistence(timeout: 10))
        XCTAssertFalse(element("signIn.apple").exists)
    }

    func testCoParentJoinsWithAnEnrollmentLink() throws {
        let parent = try api.registerParent(name: "Inviter")
        let email = TestAPI.uniqueEmail("coparent")
        let invite = try api.parentEnrollment(parent, email: email)
        launch()
        openConnectionLink(URL(string: try XCTUnwrap(invite.qrPayload))!)
        confirmServerConnection()

        element("enrollment.parent.name").waitToAppear(timeout: 15).replaceText("Co Parent")
        typeSecureText(TestAPI.password, into: element("enrollment.parent.password"))
        XCTAssertEqual(element("enrollment.parent.email").stringValue, email)
        dismissKeyboard()
        let submit = element("enrollment.parent.submit")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)], timeout: 5), .completed)
        submit.tap()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
        let family = try api.family(parent)
        XCTAssertEqual(Set(family.parents.compactMap(\.email)), [parent.email, email])
    }

    func testKidCompletesPINEnrollment() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Riley")
        let enrollment = try api.childEnrollment(parent, childId: child.id)

        launch()
        openConnectionLink(URL(string: enrollment.qrPayload)!)
        confirmServerConnection()
        let username = "riley-\(UUID().uuidString.prefix(8).lowercased())"
        element("enrollment.child.username").waitToAppear(timeout: 15).replaceText(username)
        typeSecureText("123456", into: element("enrollment.child.secret"))
        typeSecureText("123456", into: element("enrollment.child.confirmation"))
        element("enrollment.child.deviceName").replaceText("Riley's iPad")
        dismissKeyboard()
        let submit = element("enrollment.child.submit")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)], timeout: 5), .completed)
        submit.tap()

        XCTAssertTrue(app.tabBars.buttons["What I Owe"].waitForExistence(timeout: 15))
        XCTAssertTrue(text("Nothing owed right now").waitForExistence(timeout: 10))
        openTab("Settings")
        element("kidSettings.name").waitFor(label: "Riley")
        XCTAssertEqual(try api.family(parent).children.first?.pairedDeviceCount, 1)
    }

    func testInvalidChildCredentialsShowAnError() {
        launch()
        element("welcome.kid").waitToAppear(timeout: 15).tap()
        element("childLogin.username").waitToAppear().replaceText("missing-child")
        element("childLogin.secret").replaceText("123456")
        element("childLogin.submit").tap()
        element("errorBanner").waitToAppear().waitFor(label: "Error")
        XCTAssertFalse(app.tabBars.buttons["What I Owe"].exists)
    }

    func testEnrollmentDeepLinkWhileOnChildLoginScreen() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Link Kid")
        let enrollment = try api.childEnrollment(parent, childId: child.id)

        launch()
        element("welcome.kid").waitToAppear(timeout: 15).tap()
        element("childLogin.submit").waitToAppear()
        openConnectionLink(URL(string: enrollment.qrPayload)!)

        confirmServerConnection()
        XCTAssertTrue(element("enrollment.child.username").waitForExistence(timeout: 15))
    }

    func testEnrollmentDeepLinkFromWelcomeScreen() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Cold Link Kid")
        let enrollment = try api.childEnrollment(parent, childId: child.id)

        launch()
        element("welcome.kid").waitToAppear(timeout: 15)
        openConnectionLink(URL(string: enrollment.qrPayload)!)
        confirmServerConnection()

        XCTAssertTrue(element("enrollment.child.username").waitForExistence(timeout: 15), "Opening an enrollment link should show child credential setup")
    }

    private func confirmServerConnection() {
        let confirm = element("server.confirm")
        for _ in 0..<8 where !confirm.exists {
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "The server confirmation screen should appear for every connection link")
        confirm.tap()
    }

    private func openConnectionLink(_ url: URL) {
        XCUIDevice.shared.system.open(url)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
    }

    private func typeSecureText(_ text: String, into field: XCUIElement) {
        field.waitToAppear().tap()
        for character in text {
            field.typeText(String(character))
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
