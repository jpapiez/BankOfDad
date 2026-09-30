import XCTest

final class KidModeTests: BankUITestCase {
    private func launchKid(_ auth: AuthTokens) {
        launch(as: auth)
        XCTAssertTrue(app.tabBars.buttons["What I Owe"].waitForExistence(timeout: 15), "Kid tabs did not appear")
    }

    func testMyLoansCardsShowProgressNextPaymentAndBalance() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Ada")
        let bike = try api.createLoan(parent, childId: child.id, .init(title: "Bike", principal: 300, installmentCount: 3))
        try api.recordPayment(parent, loanId: bike.id, amount: 100)
        let paid = try api.createLoan(parent, childId: child.id, .init(title: "Comic", principal: 20, installmentCount: 1))
        try api.recordPayment(parent, loanId: paid.id, amount: 20)
        launchKid(kid)

        let card = element("kidLoan.\(bike.id.uiID)").waitToAppear()
        card.waitFor(label: "Bike")
        let second = try XCTUnwrap(api.loan(parent, bike.id).installments.first { $0.seq == 2 })
        for fragment in ["You've paid back 33%", "Next: \(Fmt.money(100)) on \(Fmt.date(day: second.dueDate))", Fmt.money(200)] {
            XCTAssertTrue(card.label.contains(fragment), "Card '\(card.label)' is missing '\(fragment)'")
        }
        let done = element("kidLoan.\(paid.id.uiID)").waitToAppear()
        XCTAssertTrue(done.label.contains("All caught up!"), done.label)
        XCTAssertTrue(done.label.contains("100%"), done.label)
    }

    func testWhatIOweShowsLoansAndBillsWithTheTotal() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Xan")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Drone", principal: 150, installmentCount: 3))
        let bill = try api.createBill(parent, childId: child.id, title: "Music app", amount: 12)
        let forgiven = try api.createLoan(parent, childId: child.id, .init(title: "Forgiven", principal: 40, installmentCount: 1))
        try api.cancelLoan(parent, loanId: forgiven.id)
        launchKid(kid)

        XCTAssertTrue(app.navigationBars["What I owe"].waitForExistence(timeout: 10))
        element("kidBills.header").waitToAppear()
        element("kidBill.\(bill.id.uiID)").waitToAppear().waitFor(label: "Music app")
        element("kidLoans.header").waitToAppear()
        element("kidLoan.\(loan.id.uiID)").waitToAppear().waitFor(label: "Drone")
        element("kidOwed.total").waitFor(label: "Total I owe, \(Fmt.money(162))")
        assertNoErrorBanner()
    }

    func testEmptyState() throws {
        let parent = try api.registerParent()
        let (_, kid) = try api.pairedChild(parent, name: "Bo")
        launchKid(kid)
        XCTAssertTrue(text("Nothing owed right now").waitForExistence(timeout: 10))
    }

    func testLoanDetailIsReadOnly() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Cy")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Skates", principal: 90, installmentCount: 3))
        try api.recordPayment(parent, loanId: loan.id, amount: 30, note: "Chores")
        launchKid(kid)

        element("kidLoan.\(loan.id.uiID)").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Skates"].waitForExistence(timeout: 10))
        element("loanDetail.balance").waitFor(label: Fmt.money(60))
        element("loanDetail.paid").waitFor(label: "You've paid back 33%")
        XCTAssertTrue(text("YOUR PLAN").exists || text("Your plan").exists)

        XCTAssertFalse(element("loanDetail.recordPayment").exists)
        XCTAssertFalse(element("loanDetail.cancelLoan").exists)
        XCTAssertFalse(element("loanDetail.reminders").exists)
        XCTAssertFalse(element("loanDetail.receipts").exists)

        let row = scrollTo(element("installment.2"))
        row.swipeLeft()
        XCTAssertFalse(button("Edit due date").waitForExistence(timeout: 2))
        row.tap()
        XCTAssertFalse(app.navigationBars["Edit due date"].waitForExistence(timeout: 2))
        scrollTo(element("payment.row")).waitFor(label: "Chores")
    }

    func testInboxShowsEveryNotificationTypeAndMarksThemRead() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Dex")
        // Due today (inside the 15-day reminder window) with a payment -> loanCreated, receipt, reminder.
        let current = try api.createLoan(parent, childId: child.id, .init(title: "Games", principal: 300, installmentCount: 3))
        try api.recordPayment(parent, loanId: current.id, amount: 10)
        // Ten days overdue with a flat fee -> lateFee.
        let overdue = try api.createLoan(parent, childId: child.id, .init(title: "Late one", principal: 60, installmentCount: 2, lateFeeFlat: 5, lateFeeGraceDays: 1))
        try api.backdate(parent, loanId: overdue.id, days: 10)
        try api.sweep(parent)
        let types = Set(try api.notifications(kid.accessToken).map(\.type))
        XCTAssertEqual(types, ["loanCreated", "receipt", "reminder", "lateFee"], "precondition")

        launchKid(kid)
        openTab("Inbox")
        for type in ["loanCreated", "receipt", "reminder", "lateFee"] {
            XCTAssertTrue(scrollTo(element("inbox.\(type)")).waitForExistence(timeout: 10), "Missing \(type) notification")
        }
        let lateFee = element("inbox.lateFee")
        XCTAssertTrue(lateFee.label.contains("Late one"), lateFee.label)
        // Rows are marked read as they're shown.
        lateFee.waitFor(value: "Read")

        element("inbox.markAllRead").tap()
        eventually("all read on the server") { try api.notifications(kid.accessToken, unreadOnly: true).isEmpty }
        assertNoErrorBanner()

        // A notification about a loan opens that loan.
        lateFee.tap()
        XCTAssertTrue(app.navigationBars["Late one"].waitForExistence(timeout: 10))
        element("loanDetail.late").waitFor(label: "1 late")
    }

    func testInboxEmptyState() throws {
        let parent = try api.registerParent()
        let (_, kid) = try api.pairedChild(parent, name: "Eli")
        launchKid(kid)
        openTab("Inbox")
        XCTAssertTrue(text("No messages").waitForExistence(timeout: 10))
    }

    func testKidSettingsAndSignOut() throws {
        let parent = try api.registerParent()
        let (_, kid) = try api.pairedChild(parent, name: "Fay")
        launchKid(kid)
        openTab("Settings")
        element("kidSettings.name").waitFor(label: "Fay")
        element("kidSettings.signOut").tap()
        element("welcome.kid").waitToAppear(timeout: 15)
        eventually("kid session revoked") { api.refreshStatus(kid.refreshToken) == 401 }
    }
}
