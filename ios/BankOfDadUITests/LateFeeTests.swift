import XCTest

/// Uses the Development-only test hooks to backdate installments and run the reminder/late-fee sweep.
final class LateFeeTests: BankUITestCase {
    private func overdueLoan(_ parent: Parent, child: Child, flat: Decimal? = 5, percent: Decimal? = nil, graceDays: Int = 3, backdateDays: Int = 10) throws -> LoanDetail {
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Overdue loan", principal: 300, installmentCount: 3, lateFeeFlat: flat, lateFeePercent: percent, lateFeeGraceDays: graceDays))
        try api.backdate(parent, loanId: loan.id, days: backdateDays)
        try api.sweep(parent)
        return try api.loan(parent, loan.id)
    }

    private func openLoan(_ loan: LoanDetail) {
        openTab("Owed")
        element("loanRow.\(loan.id.uiID)").waitToAppear().tap()
        element("loanDetail.balance").waitToAppear()
    }

    func testOverdueInstallmentShowsLateEverywhereAndFeeCanBeWaived() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Tess")
        let loan = try overdueLoan(parent, child: child)
        XCTAssertEqual(loan.lateFees.count, 1, "precondition: the sweep assessed a fee")
        XCTAssertEqual(loan.balance, 305)

        launch(as: parent)
        element("dashboard.late").waitFor(label: "1 late")
        element("dashboard.outstanding").waitFor(label: Fmt.money(305))

        openTab("Owed")
        element("loanRow.\(loan.id.uiID)").waitToAppear().tap()
        element("loanDetail.late").waitFor(label: "1 late")
        element("loanDetail.balance").waitFor(label: Fmt.money(305))
        scrollTo(element("installment.1")).waitFor(label: "Late")

        let fee = scrollTo(element("lateFee.1"))
        fee.waitFor(label: "Installment #1")
        XCTAssertTrue(fee.label.contains(Fmt.money(5)), fee.label)

        fee.swipeLeft()
        button("Waive").waitToAppear().tap()
        element("lateFee.1").waitFor(label: "Waived")
        scrollTo(element("loanDetail.balance"), up: false).waitFor(label: Fmt.money(300))
        eventually("fee waived") { try api.loan(parent, loan.id).lateFees.first?.waivedAt != nil }

        // A waived fee can't be waived again.
        scrollTo(element("lateFee.1")).swipeLeft()
        XCTAssertFalse(button("Waive").waitForExistence(timeout: 2))
    }

    func testPercentLateFee() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Uma")
        let loan = try overdueLoan(parent, child: child, flat: nil, percent: Decimal(string: "0.1"))

        launch(as: parent)
        openLoan(loan)
        // 10% of the missed $100 payment.
        scrollTo(element("lateFee.1")).waitFor(label: Fmt.money(10))
        element("loanDetail.terms").waitFor(label: "A late fee of 10% of the missed payment applies 3 days after a missed due date.")
    }

    func testGracePeriodDefersLateStatusAndFees() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Vic")
        let loan = try overdueLoan(parent, child: child, graceDays: 5, backdateDays: 2)
        XCTAssertTrue(loan.lateFees.isEmpty)

        launch(as: parent)
        element("dashboard.late").waitFor(label: "0 late")
        openLoan(loan)
        XCTAssertFalse(element("loanDetail.late").exists)
        XCTAssertTrue(scrollTo(element("loanDetail.noLateFees")).exists)
    }

    func testRecordingAPaymentPaysTheLateFeeFirst() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Wren")
        let loan = try overdueLoan(parent, child: child)

        launch(as: parent)
        openLoan(loan)
        element("loanDetail.recordPayment").tap()
        element("payment.amount").replaceText("105")
        element("payment.save").tap()
        element("loanDetail.balance").waitFor(label: Fmt.money(200))
        XCTAssertFalse(element("loanDetail.late").waitForExistence(timeout: 2))
        let payment = scrollTo(element("payment.row"))
        XCTAssertTrue(payment.label.contains("lateFee: \(Fmt.money(5))"), payment.label)
    }
}
