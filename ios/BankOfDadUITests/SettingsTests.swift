import XCTest

final class SettingsTests: BankUITestCase {
    private func openSettings(_ parent: Parent) {
        launch(as: parent)
        openTab("Settings")
        element("settings.familyName").waitToAppear()
    }

    func testShowsAccountAndFamily() throws {
        let parent = try api.registerParent(name: "Uncle Bob", familyName: "Bob's Bank")
        openSettings(parent)

        element("settings.name").waitFor(label: "Uncle Bob")
        element("settings.email").waitFor(label: parent.email)
        element("settings.role").waitFor(label: "parent")
        element("settings.familyName").waitFor(value: "Bob's Bank")
        element("settings.timeZone").waitFor(value: TimeZone.current.identifier)
    }

    func testEditFamilyNameAndTimeZone() throws {
        let parent = try api.registerParent()
        openSettings(parent)

        element("settings.familyName").replaceText("Renamed Family")
        element("settings.timeZone").replaceText("America/Denver")
        element("settings.save").tap()

        eventually("family saved") {
            let family = try api.family(parent)
            return family.name == "Renamed Family" && family.timeZone == "America/Denver"
        }
        assertNoErrorBanner()
        openTab("Family")
        XCTAssertTrue(app.navigationBars["Renamed Family"].waitForExistence(timeout: 10))
    }

    func testInvalidTimeZoneShowsAnError() throws {
        let parent = try api.registerParent()
        openSettings(parent)

        element("settings.timeZone").replaceText("Mars/Olympus_Mons")
        element("settings.save").tap()
        element("errorBanner").waitToAppear()
        XCTAssertEqual(try api.family(parent).timeZone, TimeZone.current.identifier)
    }

    func testSignOutReturnsToWelcomeAndRevokesTheSession() throws {
        let parent = try api.registerParent()
        openSettings(parent)

        scrollTo(element("settings.signOut")).tap()
        element("welcome.parent").waitToAppear(timeout: 15)
        eventually("refresh token revoked") { api.refreshStatus(parent.auth.refreshToken) == 401 }

        // Stays signed out after a relaunch (keychain cleared by sign out, not by the test hook).
        app.terminate()
        launch(resetKeychain: false)
        element("welcome.parent").waitToAppear(timeout: 15)
    }
}
