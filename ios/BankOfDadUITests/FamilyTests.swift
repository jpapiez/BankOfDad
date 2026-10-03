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
        XCTAssertTrue(element("avatarColor.Blue").isSelected, "Blue is the default color")
        element("avatarColor.preview").waitFor(value: "Blue")
        scrollTo(element("avatarColor.Orange")).tap()
        XCTAssertTrue(element("avatarColor.Orange").isSelected)
        XCTAssertFalse(element("avatarColor.Blue").isSelected)
        element("avatarColor.preview").waitFor(value: "Orange")
        assertNoHexCodes()
        button("addChild.add").tap()

        element("family.child.Xena.devices").waitFor(label: "0 paired devices")
        let child = try XCTUnwrap(api.family(parent).children.first { $0.displayName == "Xena" })
        XCTAssertEqual(child.avatarColor, "#FF9F1C")
        assertNoErrorBanner()
    }

    func testEditChildNameAndColorUpdatesFamilyList() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Olive", color: "#4F8EF7")
        openFamily(parent)

        element("family.child.Olive.open").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Olive"].waitForExistence(timeout: 10))
        button("childDetail.edit").tap()
        XCTAssertTrue(app.navigationBars["Edit child"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("avatarColor.Blue").waitToAppear().isSelected, "The current color is selected")

        element("editChild.name").replaceText("   ")
        XCTAssertFalse(button("editChild.save").isEnabled, "A name is required")
        element("editChild.name").replaceText("  Opal Jones ")
        dismissKeyboard()
        scrollTo(element("avatarColor.Purple")).tap()
        XCTAssertTrue(element("avatarColor.Purple").isSelected)
        XCTAssertFalse(element("avatarColor.Blue").isSelected)
        element("avatarColor.preview").waitFor(value: "Purple")
        assertNoHexCodes()
        button("editChild.save").tap()

        XCTAssertTrue(app.navigationBars["Edit child"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Opal Jones"].waitForExistence(timeout: 10), "Child detail shows the new name")
        app.navigationBars["Opal Jones"].buttons.element(boundBy: 0).tap()

        element("family.child.Opal Jones.devices").waitToAppear()
        XCTAssertFalse(element("family.child.Olive.devices").exists)
        let child = try XCTUnwrap(api.family(parent).children.first)
        XCTAssertEqual(child.displayName, "Opal Jones")
        XCTAssertEqual(child.avatarColor, "#7B61FF")
        assertNoErrorBanner()
    }

    func testEditChildWithCustomColorFromSwipeKeepsColor() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Remy", color: "#123456")
        openFamily(parent)

        element("family.child.Remy.devices").waitToAppear().swipeRight()
        button("Edit").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Edit child"].waitForExistence(timeout: 10))
        element("avatarColor.preview").waitFor(value: "Custom color")
        for name in ["Blue", "Orange", "Teal", "Red", "Purple", "Green", "Pink", "Yellow"] {
            XCTAssertFalse(scrollTo(element("avatarColor.\(name)")).isSelected, "\(name) should not be selected")
        }
        assertNoHexCodes()

        scrollTo(element("editChild.name"), up: false).replaceText("Remington")
        button("editChild.save").tap()

        element("family.child.Remington.devices").waitToAppear()
        let child = try XCTUnwrap(api.family(parent).children.first)
        XCTAssertEqual(child.displayName, "Remington")
        XCTAssertEqual(child.avatarColor, "#123456", "An unchanged custom color is kept")
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

    func testGenerateChildSetupShowsEnrollmentQR() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Yuri")
        openFamily(parent)

        element("family.child.Yuri.actions").waitToAppear().tap()
        button("Generate child setup QR").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Set Up Child Login"].waitForExistence(timeout: 10))

        element("pairingSheet.code").waitToAppear().waitFor(label: "Scan to create a username and password or PIN.")
        let payload = try XCTUnwrap(element("pairingSheet.qr").waitToAppear().value as? String)
        let components = try XCTUnwrap(URLComponents(string: payload))
        let token = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "token" })?.value)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "kind" })?.value, "child")
        let username = "yuri-\(UUID().uuidString.prefix(8).lowercased())"
        let childAuth = try api.completeChildEnrollment(token: token, username: username, secret: "123456", kind: "pin")
        XCTAssertEqual(childAuth.user.role, "child")
        XCTAssertTrue(element("pairingSheet.qr").exists)
        element("pairingSheet.expires").waitFor(label: "Expires in")
        XCTAssertTrue(element("pairingSheet.share").exists)

        button("pairingSheet.done").tap()
        XCTAssertTrue(app.navigationBars["Set Up Child Login"].waitForNonExistence(timeout: 10))
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
        XCTAssertTrue(share.label.contains("Share co-parent invitation"), share.label)
        let payload = try XCTUnwrap(share.value as? String, "The share control must expose the exact generated invitation payload")
        let components = try XCTUnwrap(URLComponents(string: payload))
        let token = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "token" })?.value)
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "kind" })?.value, "parent")
        XCTAssertTrue(anyContaining("Expires").exists)

        let coParent = try api.acceptEnrollment(token: token, email: email, name: "Mama")
        XCTAssertEqual(coParent.user.role, "parent")
        XCTAssertTrue(try api.family(parent).parents.contains { $0.displayName == "Mama" })
    }

    private func assertNoHexCodes(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(anyContaining("#").exists, "Hex codes must not be shown", file: file, line: line)
    }
}
