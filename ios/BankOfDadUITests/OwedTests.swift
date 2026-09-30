import XCTest

/// The parent's Owed tab: one place for loans and bills across all children.
final class OwedTests: BankUITestCase {
    private func openOwed(as parent: Parent) {
        launch(as: parent)
        openTab("Owed")
    }

    private func openNewMenu(_ item: String) {
        element("owed.new").waitToAppear().tap()
        button(item).waitToAppear().tap()
    }

    func testCreateALoanFromTheOwedMenu() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Quinn")
        openOwed(as: parent)

        openNewMenu("owed.new.loan")
        XCTAssertTrue(app.navigationBars["New loan"].waitForExistence(timeout: 10))
        element("newLoan.childPicker").waitFor(label: "Quinn")
        element("newLoan.title").replaceText("Skateboard")
        element("newLoan.principal").replaceText("120")
        scrollTo(element("newLoan.create")).tap()
        element("newLoan.create").waitToDisappear()
        assertNoErrorBanner()

        let loan = try XCTUnwrap(api.loans(parent).first)
        XCTAssertEqual(loan.title, "Skateboard")
        let row = element("loanRow.\(loan.id.uiID)").waitToAppear()
        XCTAssertTrue(row.label.contains("Quinn"), row.label)
    }

    func testCreateABillFromTheOwedMenuWithTheChildPicker() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Rae")
        let sam = try api.addChild(parent, name: "Sam")
        openOwed(as: parent)

        openNewMenu("owed.new.bill")
        XCTAssertTrue(app.navigationBars["New bill"].waitForExistence(timeout: 10))
        element("newBill.childPicker").waitFor(label: "Rae")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Rae pays")).firstMatch.exists)
        choose("Sam", in: element("newBill.childPicker"))
        element("newBill.childPicker").waitFor(label: "Sam")
        element("newBill.title").replaceText("Phone plan")
        element("newBill.amount").replaceText("30")
        button("newBill.create").tap()

        // Creating the bill opens it.
        element("billDetail.balance").waitFor(label: Fmt.money(30))
        assertNoErrorBanner()
        let summary = try XCTUnwrap(api.bills(parent.token).first)
        let detail = try api.bill(parent.token, summary.id)
        XCTAssertEqual(detail.title, "Phone plan")
        XCTAssertEqual(detail.childId, sam.id)

        app.navigationBars.buttons.firstMatch.tap()
        let row = element("billRow.\(summary.id.uiID)").waitToAppear()
        for fragment in ["Phone plan", "Sam", Fmt.money(30)] {
            XCTAssertTrue(row.label.contains(fragment), "Row label '\(row.label)' is missing '\(fragment)'")
        }
    }

    func testListsLoansAndBillsForAllChildrenAndOpensTheirDetails() throws {
        let parent = try api.registerParent()
        let tia = try api.addChild(parent, name: "Tia")
        let uma = try api.addChild(parent, name: "Uma")
        let loan = try api.createLoan(parent, childId: tia.id, .init(title: "Guitar", principal: 200))
        let bill = try api.createBill(parent, childId: uma.id, title: "Car insurance", amount: 90)
        openOwed(as: parent)

        let loanRow = element("loanRow.\(loan.id.uiID)").waitToAppear()
        XCTAssertTrue(loanRow.label.contains("Tia"), loanRow.label)
        let billRow = element("billRow.\(bill.id.uiID)").waitToAppear()
        XCTAssertTrue(billRow.label.contains("Uma"), billRow.label)
        XCTAssertTrue(billRow.label.contains(Fmt.money(90)), billRow.label)

        choose("Uma", in: element("owed.childPicker"))
        billRow.waitToAppear()
        loanRow.waitToDisappear()
        element("owed.noLoans").waitToAppear()
        choose("All children", in: element("owed.childPicker"))

        element("billRow.\(bill.id.uiID)").waitToAppear().tap()
        element("billDetail.balance").waitFor(label: Fmt.money(90))
        app.navigationBars.buttons.firstMatch.tap()

        element("loanRow.\(loan.id.uiID)").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["Guitar"].waitForExistence(timeout: 10))
        assertNoErrorBanner()
    }

    func testEndedBillsFilter() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Vic")
        let loan = try api.createLoan(parent, childId: child.id, .init(title: "Tablet", principal: 100))
        let bill = try api.createBill(parent, childId: child.id, title: "Gym", amount: 20, firstDueDate: Calendar.current.date(byAdding: .day, value: 5, to: Date())!)
        try api.endBill(parent.token, bill.id)
        openOwed(as: parent)

        element("loanRow.\(loan.id.uiID)").waitToAppear()
        XCTAssertFalse(element("billRow.\(bill.id.uiID)").exists, "Ended bills with nothing owed are hidden from Active")
        choose("Ended bills", in: element("owed.statusPicker"))
        element("billRow.\(bill.id.uiID)").waitToAppear().waitFor(label: "Ended")
        element("loanRow.\(loan.id.uiID)").waitToDisappear()
        assertNoErrorBanner()
    }

    func testEmptyStateOffersANewLoanAndANewBill() throws {
        let parent = try api.registerParent()
        _ = try api.addChild(parent, name: "Wes")
        openOwed(as: parent)

        XCTAssertTrue(text("Nothing owed").waitForExistence(timeout: 10))
        button("owed.empty.newBill").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["New bill"].waitForExistence(timeout: 10))
        element("newBill.childPicker").waitFor(label: "Wes")
        element("newBill.cancel").tap()
        element("newBill.cancel").waitToDisappear()

        button("owed.empty.newLoan").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars["New loan"].waitForExistence(timeout: 10))
        element("newLoan.cancel").tap()
        element("newLoan.cancel").waitToDisappear()
        assertNoErrorBanner()
    }
}
