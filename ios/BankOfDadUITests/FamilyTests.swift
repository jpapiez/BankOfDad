import XCTest

final class FamilyTests: BankUITestCase {
    private func openFamily(_ parent: Parent) {
        launch(as: parent)
        openTab("Family")
        element("family.addChild").waitToAppear()
    }

    func testTitleShowsFamilyNameAndParents() throws {
        let parent = try api.registerParent(name: "Pops", familyName: "The Testers")
        openFamily(parent)
        XCTAssertTrue(app.navigationBars["The Testers"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("family.parent.Pops").exists)
    }

    func testAddChildWithColor() throws {
        let parent = try api.registerParent()
        openFamily(parent)

        element("family.addChild").tap()
        XCTAssertTrue(app.navigationBars["Add child"].waitForExistence(timeout: 10))
        XCTAssertFalse(button("addChild.add").isEnabled, "A name is required")
        element("addChild.name").replaceText("Xena")
        choose("#FF9F1C", in: element("addChild.color"))
        button("addChild.add").tap()

        element("family.child.Xena.devices").waitFor(label: "0 paired devices")
        let child = try XCTUnwrap(api.family(parent).children.first { $0.displayName == "Xena" })
        XCTAssertEqual(child.avatarColor, "#FF9F1C")
        assertNoErrorBanner()
    }

    func testCancelAddChildFromToolbar() throws {
        let parent = try api.registerParent()
        openFamily(parent)

        element("family.addChildToolbar").tap()
        element("addChild.name").waitToAppear().replaceText("Nobody")
        button("addChild.cancel").tap()
        XCTAssertTrue(app.navigationBars["Add child"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(element("family.child.Nobody.devices").exists)
        XCTAssertTrue(try api.family(parent).children.isEmpty)
    }

    func testGeneratePairingCodeShowsAWorkingCode() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Yuri")
        openFamily(parent)

        element("family.child.Yuri.actions").waitToAppear().tap()
        button("Generate pairing code").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Pair child"].waitForExistence(timeout: 10))

        let code = element("pairingSheet.code").waitToAppear().label
        XCTAssertNotNil(code.range(of: #"^([A-Z0-9]{3}-)+[A-Z0-9]{1,3}$"#, options: .regularExpression), "Code is display-formatted: \(code)")
        XCTAssertTrue(element("pairingSheet.qr").exists)
        element("pairingSheet.expires").waitFor(label: "Expires in")
        XCTAssertTrue(element("pairingSheet.share").exists)

        // The shown code pairs a device.
        let kid = try api.pair(code: code.replacingOccurrences(of: "-", with: ""))
        XCTAssertEqual(kid.user.displayName, "Yuri")

        button("pairingSheet.done").tap()
        XCTAssertTrue(app.navigationBars["Pair child"].waitForNonExistence(timeout: 10))
    }

    func testRevokeDevicesSignsTheKidOut() throws {
        let parent = try api.registerParent()
        let (_, kid) = try api.pairedChild(parent, name: "Zoe")
        openFamily(parent)

        element("family.child.Zoe.devices").waitFor(label: "1 paired device")
        element("family.child.Zoe.actions").tap()
        button("Revoke devices").waitToAppear().tap()

        element("family.child.Zoe.devices").waitFor(label: "0 paired devices")
        XCTAssertEqual(api.refreshStatus(kid.refreshToken), 401, "The kid's session is revoked")
    }

    func testInviteCoParentProducesAnAcceptableCode() throws {
        let parent = try api.registerParent()
        openFamily(parent)

        let email = TestAPI.uniqueEmail("invitee")
        scrollTo(element("family.inviteEmail")).replaceText(email)
        scrollTo(element("family.invite")).tap()
        let share = scrollTo(element("family.inviteShare")).waitToAppear()
        let code = share.stringValue
        XCTAssertFalse(code.isEmpty)
        XCTAssertTrue(share.label.contains(code), share.label)
        XCTAssertTrue(anyContaining("Expires").exists)

        let coParent = try api.acceptInvite(code: code, email: email, name: "Mama")
        XCTAssertEqual(coParent.user.role, "parent")
        XCTAssertTrue(try api.family(parent).parents.contains { $0.displayName == "Mama" })
    }
}
