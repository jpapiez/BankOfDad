import XCTest

final class DashboardTests: BankUITestCase {
    func testEmptyDashboard() throws {
        let parent = try api.registerParent()
        launch(as: parent)

        element("dashboard.outstanding").waitFor(label: Fmt.money(0))
        element("dashboard.active").waitFor(label: "0 active")
        element("dashboard.late").waitFor(label: "0 late")
        XCTAssertTrue(text("Nothing due soon").exists)
        assertNoErrorBanner()
    }

    func testTotalsAndComingUpList() throws {
        let parent = try api.registerParent()
        let ava = try api.addChild(parent, name: "Ava")
        let ben = try api.addChild(parent, name: "Ben")
        let bike = try api.createLoan(parent, childId: ava.id, .init(title: "Bike", principal: 300, installmentCount: 3))
        let game = try api.createLoan(parent, childId: ben.id, .init(title: "Video game", principal: 120, frequency: "weekly", installmentCount: 4))
        let cancelled = try api.createLoan(parent, childId: ben.id, .init(title: "Skateboard", principal: 80, installmentCount: 2))
        try api.cancelLoan(parent, loanId: cancelled.id)
        try api.recordPayment(parent, loanId: bike.id, amount: 50)

        launch(as: parent)

        // 250 left on the bike + 120 on the game; cancelled loans don't count.
        element("dashboard.outstanding").waitFor(label: Fmt.money(370))
        element("dashboard.active").waitFor(label: "2 active")
        element("dashboard.late").waitFor(label: "0 late")

        let bikeItem = element("dashboard.upcoming.\(bike.id.uiID)").waitToAppear()
        XCTAssertTrue(bikeItem.label.contains("Bike"), bikeItem.label)
        XCTAssertTrue(bikeItem.label.contains("Ava"), bikeItem.label)
        // Remaining on installment #1 after the $50 payment.
        XCTAssertTrue(bikeItem.label.contains(Fmt.money(50)), bikeItem.label)
        XCTAssertTrue(element("dashboard.upcoming.\(game.id.uiID)").exists)
        XCTAssertFalse(element("dashboard.upcoming.\(cancelled.id.uiID)").exists)
        XCTAssertFalse(text("Nothing due soon").exists)
    }

    func testComingUpItemOpensTheLoan() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Cleo")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Tablet", principal: 200, installmentCount: 2))

        launch(as: parent)
        element("dashboard.upcoming.\(loan.id.uiID)").waitToAppear().tap()

        XCTAssertTrue(app.navigationBars["Tablet"].waitForExistence(timeout: 10))
        element("loanDetail.balance").waitFor(label: Fmt.money(200))
        element("loanDetail.terms").waitFor(label: "Cleo borrowed")
    }
}
