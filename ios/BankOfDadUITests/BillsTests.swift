import XCTest

final class BillsTests: BankUITestCase {
    private func openChild(_ name: String, as parent: Parent) {
        launch(as: parent)
        openTab("Family")
        element("family.child.\(name).open").waitToAppear().tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
    }

    func testCreateABillAndRecordAPayment() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Mia")
        openChild("Mia", as: parent)

        element("childDetail.noBills").waitToAppear()
        element("childDetail.addBill").tap()
        XCTAssertTrue(app.navigationBars["New bill"].waitForExistence(timeout: 10))
        XCTAssertFalse(button("newBill.create").isEnabled, "Create needs a name and an amount")
        element("newBill.title").replaceText("Cell phone")
        element("newBill.amount").replaceText("45")
        choose("Quarterly", in: element("newBill.frequency"))
        button("newBill.create").tap()

        // Creating the bill opens it; the first charge is due today.
        element("billDetail.balance").waitFor(label: Fmt.money(45))
        assertNoErrorBanner()
        let bill = try XCTUnwrap(api.bills(parent.token).first)
        var detail = try api.bill(parent.token, bill.id)
        XCTAssertEqual(detail.title, "Cell phone")
        XCTAssertEqual(detail.childId, child.id)
        XCTAssertEqual(detail.amount, 45)
        XCTAssertEqual(detail.frequency, "quarterly")
        XCTAssertEqual(detail.firstDueDate, TestAPI.day(Date()))
        let nextQuarter = Calendar.current.date(byAdding: .month, value: 3, to: Date())!
        XCTAssertEqual(detail.charges.map(\.dueDate), [TestAPI.day(nextQuarter), TestAPI.day(Date())])
        element("billCharge.1").waitFor(label: "Due")

        element("billDetail.recordPayment").tap()
        let amount = element("payment.amount").waitToAppear()
        XCTAssertEqual(amount.value as? String, "45", "Defaults to what's owed now")
        amount.replaceText("30")
        element("payment.note").replaceText("Allowance")
        element("payment.save").tap()
        element("payment.save").waitToDisappear()

        element("billDetail.balance").waitFor(label: Fmt.money(15))
        let payment = scrollTo(element("billPayment.row"))
        payment.waitFor(label: Fmt.money(30))
        XCTAssertTrue(payment.label.contains("Allowance"), payment.label)
        assertNoErrorBanner()

        detail = try api.bill(parent.token, bill.id)
        XCTAssertEqual(detail.amountPaid, 30)
        XCTAssertEqual(detail.balance, 15)
        XCTAssertEqual(detail.payments.first?.note, "Allowance")
        let notifications = try api.notifications(kid.accessToken)
        XCTAssertTrue(notifications.contains { $0.type == "billCreated" && $0.billId == bill.id })
        XCTAssertTrue(notifications.contains { $0.type == "receipt" && $0.billId == bill.id })
    }

    func testChangeTheAmountThenEndTheBill() throws {
        let parent = try api.registerParent()
        let child = try api.addChild(parent, name: "Noah")
        let bill = try api.createBill(parent, childId: child.id, title: "Rent", amount: 400)
        openChild("Noah", as: parent)

        element("childDetail.bill.Rent").waitToAppear().tap()
        element("billDetail.balance").waitFor(label: Fmt.money(400))
        element("billDetail.edit").tap()
        element("editBill.amount").waitToAppear().replaceText("450")
        element("editBill.save").tap()
        element("editBill.save").waitToDisappear()
        element("billDetail.amount").waitFor(label: Fmt.money(450))

        // Only the charge that isn't due yet picks up the new amount.
        var detail = try api.bill(parent.token, bill.id)
        XCTAssertEqual(detail.amount, 450)
        XCTAssertEqual(detail.charges.map(\.amount), [450, 400])
        XCTAssertEqual(detail.balance, 400)

        element("billDetail.end").tap()
        button("billDetail.confirmEnd").waitToAppear().tap()
        element("billDetail.status").waitFor(label: "Ended")
        XCTAssertTrue(element("billDetail.edit").waitForNonExistence(timeout: 5))
        XCTAssertTrue(element("billDetail.recordPayment").exists, "What's already due can still be paid")
        detail = try api.bill(parent.token, bill.id)
        XCTAssertEqual(detail.status, "ended")
        XCTAssertEqual(detail.charges.map(\.dueDate), [TestAPI.day(Date())])
    }

    func testKidSeesTheirBillReadOnly() throws {
        let parent = try api.registerParent()
        let (child, kid) = try api.pairedChild(parent, name: "Ola")
        let bill = try api.createBill(parent, childId: child.id, title: "Car insurance", amount: 80)
        let sibling = try api.addChild(parent, name: "Pip")
        _ = try api.createBill(parent, childId: sibling.id, title: "Streaming", amount: 10)
        launch(as: kid)

        element("kidBills.header").waitToAppear()
        let card = element("kidBill.\(bill.id.uiID)").waitToAppear()
        XCTAssertTrue(card.label.contains("Car insurance"), card.label)
        XCTAssertFalse(anyContaining("Streaming").exists, "Kids only see their own bills")
        card.tap()
        element("billDetail.balance").waitFor(label: Fmt.money(80))
        XCTAssertFalse(element("billDetail.recordPayment").exists)
        XCTAssertFalse(element("billDetail.edit").exists)
        XCTAssertFalse(element("billDetail.reminders").exists)
    }
}
