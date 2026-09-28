import XCTest

final class LoanDetailTests: BankUITestCase {
    private func openLoan(_ loan: LoanDetail, as parent: Parent) {
        launch(as: parent)
        openTab("Loans")
        element("loanRow.\(loan.id.uiID)").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars[loan.title].waitForExistence(timeout: 10))
        element("loanDetail.balance").waitToAppear()
    }

    func testHeaderTermsScheduleAndEmptySections() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Milo")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Guitar", principal: 300, installmentCount: 3))
        openLoan(loan, as: parent)

        element("loanDetail.balance").waitFor(label: Fmt.money(300))
        element("loanDetail.status").waitFor(label: "Active")
        element("loanDetail.paid").waitFor(label: "Paid \(Fmt.money(0))")
        XCTAssertFalse(element("loanDetail.late").exists)
        let terms = element("loanDetail.terms").label
        XCTAssertTrue(terms.contains("Milo borrowed \(Fmt.money(300)) for \"Guitar\" with no interest, repaid in 3 monthly payments of \(Fmt.money(100))"), terms)
        XCTAssertTrue(anyContaining("Monthly").exists)

        for installment in loan.installments {
            let row = scrollTo(element("installment.\(installment.seq)"))
            row.waitFor(label: "Payment #\(installment.seq)")
            XCTAssertTrue(row.label.contains(Fmt.date(day: installment.dueDate)), row.label)
            XCTAssertTrue(row.label.contains(Fmt.money(100)), row.label)
        }
        XCTAssertTrue(scrollTo(element("loanDetail.noLateFees")).exists)
        scrollTo(element("loanDetail.noPayments")).waitFor(label: "No payments recorded yet.")
    }

    func testRecordPaymentUpdatesBalanceAndSendsReceipt() throws {
        let parent = try api.registerParent()
        let (child, kidAuth) = try api.pairedChild(parent, name: "Nia")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Shoes", principal: 300, installmentCount: 3))
        openLoan(loan, as: parent)

        element("loanDetail.recordPayment").waitToAppear().tap()
        let amount = element("payment.amount").waitToAppear()
        XCTAssertEqual(amount.stringValue, "100", "Amount is prefilled with the next payment")
        XCTAssertTrue(element("payment.paidOn").exists)
        amount.replaceText("150")
        element("payment.note").replaceText("Birthday money")
        element("payment.save").tap()
        element("payment.save").waitToDisappear()

        element("loanDetail.balance").waitFor(label: Fmt.money(150))
        element("loanDetail.paid").waitFor(label: "Paid \(Fmt.money(150))")
        scrollTo(element("installment.1")).waitFor(label: "Paid")
        let payment = scrollTo(element("payment.row"))
        payment.waitFor(label: Fmt.money(150))
        XCTAssertTrue(payment.label.contains("Birthday money"), payment.label)
        assertNoErrorBanner()

        XCTAssertEqual(try api.loan(parent, loan.id).payments.first?.note, "Birthday money")
        eventually("receipt sent to the kid") {
            try api.notifications(kidAuth.accessToken).contains { $0.type == "receipt" }
        }
    }

    func testOverpaymentIsBlocked() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Omar")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Drone", principal: 90))
        openLoan(loan, as: parent)

        element("loanDetail.recordPayment").waitToAppear().tap()
        element("payment.amount").replaceText("1000")
        element("errorBanner").waitFor(label: "cannot exceed the remaining balance")
        // Toolbar identifiers are also set on a wrapper element; the Button carries the enabled state.
        XCTAssertFalse(button("payment.save").isEnabled)
        element("payment.cancel").tap()
        element("payment.amount").waitToDisappear()
        XCTAssertTrue(try api.loan(parent, loan.id).payments.isEmpty)
    }

    func testPayingInFullMarksLoanPaidOffAndHidesActions() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Pia")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Book", principal: 40, installmentCount: 2))
        openLoan(loan, as: parent)

        element("loanDetail.recordPayment").waitToAppear().tap()
        element("payment.amount").replaceText("40")
        element("payment.save").tap()

        element("loanDetail.status").waitFor(label: "Paid off")
        element("loanDetail.balance").waitFor(label: Fmt.money(0))
        XCTAssertTrue(element("loanDetail.recordPayment").waitForNonExistence(timeout: 5))
        XCTAssertFalse(element("loanDetail.cancelLoan").exists)
        XCTAssertEqual(try api.loan(parent, loan.id).status, "paidOff")
    }

    func testNotificationTogglesPersist() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Quin")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Watch"))
        openLoan(loan, as: parent)

        let reminders = element("loanDetail.reminders").waitToAppear()
        XCTAssertTrue(reminders.isOn)
        reminders.setSwitch(false)
        eventually("reminders off") { try !api.loan(parent, loan.id).sendReminders }

        let receipts = element("loanDetail.receipts")
        XCTAssertTrue(receipts.isOn)
        receipts.setSwitch(false)
        eventually("receipts off") { try !api.loan(parent, loan.id).sendReceipts }

        reminders.setSwitch(true)
        eventually("reminders back on") { try api.loan(parent, loan.id).sendReminders }
        assertNoErrorBanner()
    }

    func testEditDueDateFromSwipeAction() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Remy")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Telescope", principal: 300, installmentCount: 3))
        let second = loan.installments[1]
        let current = TestAPI.date(second.dueDate)
        let calendar = Calendar.current
        // Move it by one day within the same month so the calendar doesn't need paging.
        let newDate = calendar.date(byAdding: .day, value: calendar.component(.day, from: current) > 1 ? -1 : 1, to: current)!
        openLoan(loan, as: parent)

        let row = scrollTo(element("installment.2"))
        row.swipeLeft()
        button("Edit due date").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Edit due date"].waitForExistence(timeout: 10))
        pickDate(newDate, in: element("dueDate.picker"))
        element("dueDate.save").tap()
        element("dueDate.save").waitToDisappear()

        scrollTo(element("installment.2")).waitFor(label: Fmt.date(newDate))
        eventually("due date saved") {
            try api.loan(parent, loan.id).installments[1].dueDate == TestAPI.day(newDate)
        }
        assertNoErrorBanner()
    }

    func testCancelLoanAfterConfirmation() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Sol")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Kayak"))
        openLoan(loan, as: parent)

        element("loanDetail.cancelLoan").waitToAppear().tap()
        XCTAssertTrue(text("Cancel this loan?").waitForExistence(timeout: 5))
        XCTAssertTrue(text("Cancelled loans stop new reminders and payments.").exists)
        button("Cancel loan").tap()

        element("loanDetail.status").waitFor(label: "Cancelled")
        XCTAssertTrue(element("loanDetail.recordPayment").waitForNonExistence(timeout: 5))
        XCTAssertEqual(try api.loan(parent, loan.id).status, "cancelled")
    }

    /// Opens a compact DatePicker's calendar and taps the given day (must be in the displayed month).
    private func pickDate(_ date: Date, in picker: XCUIElement) {
        picker.waitToAppear()
        let field = picker.buttons.firstMatch.exists ? picker.buttons.firstMatch : picker
        field.tap()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", formatter.string(from: date))).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5), "Day \(formatter.string(from: date)) not in calendar")
        day.tap()
        // Close the calendar popover.
        app.navigationBars["Edit due date"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
