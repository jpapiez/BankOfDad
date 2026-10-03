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

    func testCoParentJoinsWithAnInviteCode() throws {
        let parent = try api.registerParent(name: "Inviter")
        let invite = try api.invite(parent)
        launch()
        element("welcome.parent").waitToAppear(timeout: 15).tap()
        element("signIn.toggleInvite").waitToAppear().tap()
        XCTAssertEqual(element("signIn.submit").label, "Accept invite")

        let email = TestAPI.uniqueEmail("coparent")
        element("signIn.email").replaceText(email)
        element("signIn.password").replaceText(TestAPI.password)
        element("signIn.displayName").replaceText("Co Parent")
        element("signIn.inviteCode").replaceText(invite.inviteCode.lowercased())
        XCTAssertTrue(element("signIn.inviteCode").stringValue.contains("-"), "Invite code is display-formatted with dashes")
        element("signIn.submit").tap()

        XCTAssertTrue(app.tabBars.buttons["Dashboard"].waitForExistence(timeout: 15))
        let family = try api.family(parent)
        XCTAssertEqual(Set(family.parents.compactMap(\.email)), [parent.email, email])
    }

    func testKidPairsWithATypedCode() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Riley")
        let code = try api.pairingCode(parent, childId: child.id)

        launch()
        element("welcome.kid").waitToAppear(timeout: 15).tap()
        XCTAssertTrue(element("pairing.scan").waitForExistence(timeout: 5), "QR scanning needs a camera; only the entry point is checked")
        let join = element("pairing.join")
        XCTAssertFalse(join.isEnabled)

        let raw = code.code.replacingOccurrences(of: "-", with: "").lowercased()
        element("pairing.code").replaceText(raw)
        // Typed input is display-formatted with dashes (synthesized fast typing can outrun the
        // re-formatting of the last characters, so compare the normalized value).
        let typed = element("pairing.code").stringValue
        XCTAssertTrue(typed.contains("-"), "Pairing code field shows dashes, got \(typed)")
        XCTAssertEqual(typed.replacingOccurrences(of: "-", with: "").uppercased(), raw.uppercased())
        element("pairing.deviceName").replaceText("Riley's iPad")
        join.tap()

        XCTAssertTrue(app.tabBars.buttons["What I Owe"].waitForExistence(timeout: 15))
        XCTAssertTrue(text("Nothing owed right now").waitForExistence(timeout: 10))
        openTab("Settings")
        element("kidSettings.name").waitFor(label: "Riley")
        XCTAssertEqual(try api.family(parent).children.first?.pairedDeviceCount, 1)
    }

    func testInvalidPairingCodeShowsAnError() {
        launch()
        element("welcome.kid").waitToAppear(timeout: 15).tap()
        element("pairing.code").replaceText("ZZZZZZZZ")
        element("pairing.join").tap()
        element("errorBanner").waitToAppear().waitFor(label: "Error")
        XCTAssertFalse(app.tabBars.buttons["What I Owe"].exists)
    }

    func testPairingDeepLinkWhileOnPairingScreen() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Link Kid")
        let code = try api.pairingCode(parent, childId: child.id)

        launch()
        element("welcome.kid").waitToAppear(timeout: 15).tap()
        element("pairing.join").waitToAppear()
        // Opens the link through the system (like tapping it elsewhere) without relaunching the app.
        XCUIDevice.shared.system.open(URL(string: code.qrPayload)!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirm = springboard.buttons["Open"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }

        XCTAssertTrue(app.tabBars.buttons["What I Owe"].waitForExistence(timeout: 15))
    }

    func testPairingDeepLinkFromWelcomeScreen() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Cold Link Kid")
        let code = try api.pairingCode(parent, childId: child.id)

        launch()
        element("welcome.kid").waitToAppear(timeout: 15)
        // Launches the app from the link, like scanning the parent's QR code with the Camera app.
        app.open(URL(string: code.qrPayload)!)

        XCTAssertTrue(app.tabBars.buttons["What I Owe"].waitForExistence(timeout: 15), "Opening a pairing link from the Welcome screen should pair the device")
    }
}
