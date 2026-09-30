import XCTest

final class NewLoanTests: BankUITestCase {
    private func openNewLoan(for parent: Parent) {
        launch(as: parent)
        openTab("Owed")
        element("owed.new").waitToAppear().tap()
        button("owed.new.loan").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["New loan"].waitForExistence(timeout: 10))
    }

    func testPreviewAndCreateASimpleLoan() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Iris")
        openNewLoan(for: parent)

        element("newLoan.childPicker").waitFor(label: "Iris")
        XCTAssertFalse(scrollTo(element("newLoan.create")).isEnabled, "Create needs a title")
        scrollTo(element("newLoan.title"), up: false)
        element("newLoan.title").replaceText("New bike")
        element("newLoan.principal").replaceText("300")
        step(element("newLoan.installments"), by: -3)
        element("newLoan.installments").waitFor(label: "3 payments")

        scrollTo(element("newLoan.preview")).tap()
        scrollTo(element("newLoan.preview.total"))
        element("newLoan.preview.payment").waitFor(label: Fmt.money(100))
        element("newLoan.preview.interest").waitFor(label: Fmt.money(0))
        element("newLoan.preview.total").waitFor(label: Fmt.money(300))
        for seq in 1...3 {
            let row = scrollTo(element("newLoan.preview.installment.\(seq)"))
            row.waitFor(label: "#\(seq)")
            XCTAssertTrue(row.label.contains(Fmt.money(100)), row.label)
        }
        XCTAssertTrue(element("newLoan.preview.installment.1").label.contains(Fmt.date(Date())), "First payment defaults to today")

        scrollTo(element("newLoan.create")).tap()
        element("newLoan.create").waitToDisappear()
        assertNoErrorBanner()

        let loans = try api.loans(parent)
        XCTAssertEqual(loans.count, 1)
        let loan = try api.loan(parent, loans[0].id)
        XCTAssertEqual(loan.title, "New bike")
        XCTAssertEqual(loan.principal, 300)
        XCTAssertEqual(loan.installmentCount, 3)
        XCTAssertEqual(loan.frequency, "monthly")
        XCTAssertFalse(loan.interestEnabled)
        XCTAssertNil(loan.lateFeeFlat)
        XCTAssertTrue(loan.sendReminders)
        XCTAssertTrue(loan.sendReceipts)

        // The list refreshes when the sheet closes.
        element("loanRow.\(loan.id.uiID)").waitToAppear()
        let notifications = try api.notifications(parent.token)
        XCTAssertTrue(notifications.isEmpty, "Parents don't get the kid's loan-created notification")
    }

    func testInterestFrequencyLateFeesAndNotificationOptions() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Jay")
        let kay = try api.addChild(parent, name: "Kay")
        openNewLoan(for: parent)

        choose("Kay", in: element("newLoan.childPicker"))
        element("newLoan.title").replaceText("Phone")
        element("newLoan.principal").replaceText("400")
        element("newLoan.interest").setSwitch(true)
        element("newLoan.apr").waitToAppear().replaceText("12")
        choose("Weekly", in: element("newLoan.frequency"))
        step(element("newLoan.installments"), by: -2)
        element("newLoan.installments").waitFor(label: "4 payments")

        scrollTo(element("newLoan.lateFees")).setSwitch(true)
        element("newLoan.lateFeeFlat").waitToAppear().replaceText("2")
        element("newLoan.lateFeePercent").replaceText("10")
        step(scrollTo(element("newLoan.graceDays")), by: 2)
        element("newLoan.graceDays").waitFor(label: "Grace days: 5")
        scrollTo(element("newLoan.reminders")).setSwitch(false)
        XCTAssertTrue(element("newLoan.receipts").isOn)

        scrollTo(element("newLoan.preview")).tap()
        let interest = scrollTo(element("newLoan.preview.interest")).waitToAppear()
        XCTAssertFalse(interest.label.contains(Fmt.money(0)), "12% APR should produce interest: \(interest.label)")
        scrollTo(element("newLoan.create")).tap()
        element("newLoan.create").waitToDisappear()
        assertNoErrorBanner()

        let summary = try XCTUnwrap(api.loans(parent).first)
        let loan = try api.loan(parent, summary.id)
        XCTAssertEqual(loan.title, "Phone")
        XCTAssertEqual(try api.family(parent).children.first { $0.id == kay.id }?.displayName, "Kay")
        XCTAssertTrue(loan.interestEnabled)
        XCTAssertEqual(loan.annualRate, Decimal(string: "0.12"))
        XCTAssertEqual(loan.frequency, "weekly")
        XCTAssertEqual(loan.installmentCount, 4)
        XCTAssertEqual(loan.lateFeeFlat, 2)
        XCTAssertEqual(loan.lateFeePercent, Decimal(string: "0.1"))
        XCTAssertEqual(loan.lateFeeGraceDays, 5)
        XCTAssertFalse(loan.sendReminders)
        XCTAssertTrue(loan.sendReceipts)
        XCTAssertGreaterThan(loan.balance, 400)
    }

    func testCancelDiscardsTheDraft() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Lia")
        openNewLoan(for: parent)

        element("newLoan.title").replaceText("Never mind")
        element("newLoan.principal").replaceText("50")
        element("newLoan.cancel").tap()
        XCTAssertTrue(app.navigationBars["New loan"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(try api.loans(parent).isEmpty)
    }

    func testCreateIsDisabledWithoutAChild() throws {
        let parent = try api.registerParent()
        openNewLoan(for: parent)

        element("newLoan.title").replaceText("No borrower")
        element("newLoan.principal").replaceText("10")
        XCTAssertFalse(scrollTo(element("newLoan.create")).isEnabled)
        XCTAssertFalse(scrollTo(element("newLoan.preview"), up: false).isEnabled)
    }
}
