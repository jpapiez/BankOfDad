import XCTest

final class LoansListTests: BankUITestCase {
    private func row(_ loan: LoanDetail) -> XCUIElement { element("loanRow.\(loan.id.uiID)") }

    /// Regression test for #2: the status filter sent `PaidOff` instead of `paidOff` and showed an error banner.
    func testStatusFilterShowsActivePaidOffAndCancelledLoans() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Dana")
        let active = try api.createLoan(parent, childId: child.id, .init(title: "Active loan", principal: 90))
        let paid = try api.createLoan(parent, childId: child.id, .init(title: "Paid loan", principal: 60, installmentCount: 2))
        try api.recordPayment(parent, loanId: paid.id, amount: 60)
        let cancelled = try api.createLoan(parent, childId: child.id, .init(title: "Cancelled loan", principal: 30, installmentCount: 1))
        try api.cancelLoan(parent, loanId: cancelled.id)

        launch(as: parent)
        openTab("Owed")

        row(active).waitToAppear()
        XCTAssertFalse(row(paid).exists)
        XCTAssertFalse(row(cancelled).exists)
        assertNoErrorBanner()

        choose("Paid off loans", in: element("owed.statusPicker"))
        row(paid).waitToAppear()
        row(paid).waitFor(label: "Paid off")
        XCTAssertFalse(row(active).exists)
        XCTAssertFalse(row(cancelled).exists)
        assertNoErrorBanner()

        choose("Cancelled loans", in: element("owed.statusPicker"))
        row(cancelled).waitToAppear()
        row(cancelled).waitFor(label: "Cancelled")
        XCTAssertFalse(row(active).exists)
        XCTAssertFalse(row(paid).exists)
        assertNoErrorBanner()

        choose("Active", in: element("owed.statusPicker"))
        row(active).waitToAppear()
        XCTAssertFalse(row(cancelled).exists)
        assertNoErrorBanner()
    }

    func testChildFilter() throws {
        let parent = try api.registerParent()
        let eve = try api.addChild(parent, name: "Eve")
        let finn = try api.addChild(parent, name: "Finn")
        let eveLoan = try api.createLoan(parent, childId: eve.id, .init(title: "Eve's scooter"))
        let finnLoan = try api.createLoan(parent, childId: finn.id, .init(title: "Finn's lego"))

        launch(as: parent)
        openTab("Owed")
        row(eveLoan).waitToAppear()
        row(finnLoan).waitToAppear()

        choose("Finn", in: element("owed.childPicker"))
        row(finnLoan).waitToAppear()
        row(eveLoan).waitToDisappear()
        assertNoErrorBanner()

        choose("All children", in: element("owed.childPicker"))
        row(eveLoan).waitToAppear()
        row(finnLoan).waitToAppear()
    }

    func testRowShowsTitleChildNextPaymentBalanceAndStatus() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Gus")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Headphones", principal: 300, installmentCount: 3))
        try api.recordPayment(parent, loanId: loan.id, amount: 25)

        launch(as: parent)
        openTab("Owed")
        let label = row(loan).waitToAppear().label
        for fragment in ["Headphones", "Gus", "Next: \(Fmt.money(75)) on \(Fmt.date(day: loan.firstDueDate))", Fmt.money(275), "Active"] {
            XCTAssertTrue(label.contains(fragment), "Row label '\(label)' is missing '\(fragment)'")
        }
    }

    func testEmptyState() throws {
        let parent = try api.registerParent()
        launch(as: parent)
        openTab("Owed")
        XCTAssertTrue(text("Nothing owed").waitForExistence(timeout: 10))
        choose("Cancelled loans", in: element("owed.statusPicker"))
        XCTAssertTrue(text("Nothing found").waitForExistence(timeout: 10))
        assertNoErrorBanner()
    }

    func testRowOpensLoanDetail() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Hana")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Camera", principal: 150))

        launch(as: parent)
        openTab("Owed")
        row(loan).waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Camera"].waitForExistence(timeout: 10))
        element("loanDetail.balance").waitFor(label: Fmt.money(150))
    }
}
