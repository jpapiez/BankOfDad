import XCTest
@testable import BankOfDad

/// Demo mode runs entirely on-device, so these tests exercise the real demo services end to end.
final class DemoModeTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore() -> DemoStore { DemoStore(referenceDate: reference) }

    @MainActor
    func testExitingDemoWithoutAConfiguredServerReturnsToNeedsServer() async {
        let environment = AppEnvironment()
        await environment.forgetServer()
        await environment.enterDemo(role: .parent, referenceDate: reference)

        await environment.exitDemo()

        XCTAssertFalse(environment.isDemo)
        XCTAssertEqual(environment.authSession.state, .needsServer)
    }

    @MainActor
    func testExitingDemoWithAConfiguredServerReturnsToSignedOut() async throws {
        let profile = ServerProfile(
            id: UUID(),
            origin: try ServerOriginPolicy.validate("http://localhost:8080"),
            familyName: "Configured Family",
            capabilities: .legacy,
            childPin: .standard
        )
        let environment = AppEnvironment(testingProfile: profile)
        await environment.enterDemo(role: .parent, referenceDate: reference)

        await environment.exitDemo()

        XCTAssertFalse(environment.isDemo)
        XCTAssertEqual(environment.authSession.state, .signedOut)
    }

    // MARK: - Seed

    func testSeedIsDeterministicForTheSameReferenceDate() async throws {
        let first = DemoSeed.make(referenceDate: reference)
        let second = DemoSeed.make(referenceDate: reference)

        XCTAssertEqual(first.children.map(\.id), second.children.map(\.id))
        XCTAssertEqual(first.loans.map(\.id), second.loans.map(\.id))
        XCTAssertEqual(first.loans.map(\.balance), second.loans.map(\.balance))
        XCTAssertEqual(first.bills.map { $0.charges.map(\.dueDate) }, second.bills.map { $0.charges.map(\.dueDate) })
        XCTAssertEqual(first.loans.flatMap { $0.installments.map(\.id) }, second.loans.flatMap { $0.installments.map(\.id) })
    }

    func testSeedTellsACompleteStory() async throws {
        let store = makeStore()
        let family = await store.family()
        XCTAssertEqual(family.children.count, 2, "Screenshots need two children")
        XCTAssertTrue(family.children.allSatisfy { $0.avatarColor?.isEmpty == false })

        let loans = await store.loanSummaries(status: nil, childId: nil)
        XCTAssertTrue(loans.contains { $0.status == .active }, "Needs an active loan")
        XCTAssertTrue(loans.contains { $0.status == .paidOff }, "Needs a paid-off loan")
        XCTAssertTrue(loans.contains { $0.lateInstallments > 0 }, "Needs an overdue loan for the late-fee story")
        XCTAssertTrue(loans.contains { $0.amountPaid > 0 }, "Needs repayment progress")

        let overdue = try XCTUnwrap(loans.first { $0.lateInstallments > 0 })
        let detail = try await store.loanDetail(overdue.id)
        XCTAssertFalse(detail.lateFees.isEmpty, "An overdue installment should have collected a late fee")
        XCTAssertGreaterThan(detail.outstandingFees, 0)
        XCTAssertFalse(detail.payments.isEmpty)
        XCTAssertFalse(detail.termsSummary.isEmpty)

        let bills = await store.billSummaries(status: nil, childId: nil)
        XCTAssertEqual(bills.count, 2)
        let billDetail = try await store.billDetail(bills[0].id)
        XCTAssertFalse(billDetail.charges.isEmpty, "Recurring bills should have generated charges")

        let dashboard = await store.dashboard()
        XCTAssertGreaterThan(dashboard.totalOutstanding, 0)
        XCTAssertGreaterThan(dashboard.activeLoans, 0)
        XCTAssertGreaterThan(dashboard.lateInstallments, 0)
        XCTAssertFalse(dashboard.upcoming.isEmpty)
        XCTAssertEqual(dashboard.activeBills, 2)
        XCTAssertFalse(dashboard.upcomingBills?.isEmpty ?? true)

        let inbox = await store.notifications(unreadOnly: false)
        XCTAssertTrue(inbox.contains { $0.type == .reminder })
        XCTAssertTrue(inbox.contains { $0.type == .receipt })
        XCTAssertTrue(inbox.contains { $0.type == .lateFee })
        XCTAssertTrue(inbox.contains { $0.readAt == nil }, "Inbox needs unread items to show a badge")
    }

    func testSeededLoanTotalsAreSelfConsistent() async throws {
        let store = makeStore()
        for summary in await store.loanSummaries(status: nil, childId: nil) {
            let detail = try await store.loanDetail(summary.id)
            let scheduled = detail.installments.reduce(Decimal(0)) { $0 + $1.amountDue }
            XCTAssertEqual(scheduled, detail.totalRepayable)
            let paid = detail.payments.reduce(Decimal(0)) { $0 + $1.amount }
            XCTAssertEqual(paid, detail.amountPaid)
            for payment in detail.payments {
                let allocated = payment.allocations.reduce(Decimal(0)) { $0 + $1.amount }
                XCTAssertEqual(allocated, payment.amount, "Every payment must be fully allocated")
            }
        }
    }

    // MARK: - Mutations

    func testRecordingAPaymentUpdatesEverySurface() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let notifications = DemoNotificationService(store: store)

        let activeLoans = try await loans.parentLoans(status: .active, childId: nil)
        let active = try XCTUnwrap(activeLoans.first { $0.balance > 0 })
        let before = try await loans.dashboard()
        await store.setRole(.child, childId: active.childId)
        let inboxBefore = try await notifications.notifications().count
        await store.setRole(.parent, childId: nil)

        let amount = Decimal(25)
        let payment = try await loans.recordPayment(loanId: active.id, amount: amount, paidOn: CalendarDate(reference), note: "Chores")
        XCTAssertEqual(payment.amount, amount)

        let detail = try await loans.loan(active.id)
        XCTAssertEqual(detail.balance, active.balance - amount)
        XCTAssertEqual(detail.amountPaid, active.amountPaid + amount)

        let after = try await loans.dashboard()
        XCTAssertEqual(after.totalOutstanding, before.totalOutstanding - amount)

        await store.setRole(.child, childId: active.childId)
        let kidView = try await loans.myLoans()
        XCTAssertEqual(kidView.first { $0.id == active.id }?.balance, detail.balance)
        let inboxAfter = try await notifications.notifications()
        XCTAssertEqual(inboxAfter.count, inboxBefore + 1, "A receipt should land in the kid's Inbox")
        XCTAssertEqual(inboxAfter.first?.type, .receipt)
    }

    func testPayingOffALoanClosesIt() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let activeLoans = try await loans.parentLoans(status: .active, childId: nil)
        let active = try XCTUnwrap(activeLoans.first)
        _ = try await loans.recordPayment(loanId: active.id, amount: active.balance, paidOn: CalendarDate(reference), note: nil)
        let detail = try await loans.loan(active.id)
        XCTAssertEqual(detail.status, .paidOff)
        XCTAssertEqual(detail.balance, 0)
    }

    func testOverpaymentIsRejected() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let activeLoans = try await loans.parentLoans(status: .active, childId: nil)
        let active = try XCTUnwrap(activeLoans.first)
        do {
            _ = try await loans.recordPayment(loanId: active.id, amount: active.balance + 50, paidOn: CalendarDate(reference), note: nil)
            XCTFail("Paying more than the balance should fail")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    func testCreatingALoanAndBillAppearsImmediately() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let bills = DemoBillService(store: store)
        let family = await store.family()
        let childId = try XCTUnwrap(family.children.first?.id)

        let input = LoanTermsInput(childId: childId, title: "Headphones", principal: 90, interestEnabled: false, annualRate: 0, frequency: .weekly, installmentCount: 3, firstDueDate: CalendarDate(reference), lateFeeFlat: 2, lateFeePercent: nil, lateFeeGraceDays: 2, sendReminders: true, sendReceipts: true)
        let preview = try await loans.preview(input)
        XCTAssertEqual(preview.installments.count, 3)
        XCTAssertEqual(preview.totalRepayable, 90)

        let created = try await loans.create(input)
        XCTAssertEqual(created.title, "Headphones")
        let childLoans = try await loans.parentLoans(status: nil, childId: childId)
        XCTAssertTrue(childLoans.contains { $0.id == created.id })

        let bill = try await bills.create(BillInput(childId: childId, title: "Streaming", amount: 10, frequency: .monthly, firstDueDate: CalendarDate(reference), lateFeeFlat: 1, lateFeePercent: nil, lateFeeGraceDays: 1, sendReminders: true, sendReceipts: true))
        XCTAssertFalse(bill.charges.isEmpty)
        let allBills = try await bills.bills()
        XCTAssertTrue(allBills.contains { $0.id == bill.id })
    }

    func testWaivingALateFeeRemovesItFromTheBalance() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let activeLoans = try await loans.parentLoans(status: .active, childId: nil)
        let overdue = try XCTUnwrap(activeLoans.first { $0.lateInstallments > 0 })
        let before = try await loans.loan(overdue.id)
        let fee = try XCTUnwrap(before.lateFees.first { $0.waivedAt == nil && $0.amountPaid < $0.amount })
        let after = try await loans.waiveFee(loanId: overdue.id, lateFeeId: fee.id)
        XCTAssertEqual(after.outstandingFees, before.outstandingFees - (fee.amount - fee.amountPaid))
        XCTAssertNotNil(after.lateFees.first { $0.id == fee.id }?.waivedAt)
    }

    func testResetRestoresTheSeed() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let before = try await loans.dashboard()
        let activeLoans = try await loans.parentLoans(status: .active, childId: nil)
        let active = try XCTUnwrap(activeLoans.first)
        _ = try await loans.recordPayment(loanId: active.id, amount: 10, paidOn: CalendarDate(reference), note: nil)
        let mutated = try await loans.dashboard()
        XCTAssertNotEqual(mutated.totalOutstanding, before.totalOutstanding)

        await store.reset()
        let after = try await loans.dashboard()
        XCTAssertEqual(after.totalOutstanding, before.totalOutstanding)
        XCTAssertEqual(after.activeLoans, before.activeLoans)
    }

    // MARK: - Role scoping

    func testKidOnlySeesTheirOwnData() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let notifications = DemoNotificationService(store: store)
        let bills = DemoBillService(store: store)
        let children = await store.children()
        let maya = try XCTUnwrap(children.first)

        await store.setRole(.child, childId: maya.id)
        let mine = try await loans.myLoans()
        XCTAssertFalse(mine.isEmpty)
        XCTAssertTrue(mine.allSatisfy { $0.childId == maya.id })
        let myBills = try await bills.bills()
        XCTAssertTrue(myBills.allSatisfy { $0.childId == maya.id })
        let myInbox = try await notifications.notifications()
        XCTAssertFalse(myInbox.isEmpty)

        let allLoans = try await loans.parentLoans(status: nil, childId: nil)
        let othersLoan = try XCTUnwrap(allLoans.first { $0.childId != maya.id })
        do {
            _ = try await loans.myLoan(othersLoan.id)
            XCTFail("A kid must not be able to open a sibling's loan")
        } catch {
            XCTAssertTrue(error is APIError)
        }
    }

    func testMarkingInboxReadOnlyAffectsTheActiveKid() async throws {
        let store = makeStore()
        let notifications = DemoNotificationService(store: store)
        let children = await store.children()
        let theo = try XCTUnwrap(children.last)

        await store.setRole(.child, childId: theo.id)
        try await notifications.markAllRead()
        let theoUnread = try await notifications.notifications(unreadOnly: true)
        XCTAssertTrue(theoUnread.isEmpty)

        await store.setRole(.parent, childId: nil)
        let familyUnread = try await notifications.notifications(unreadOnly: true)
        XCTAssertFalse(familyUnread.isEmpty, "The other child's unread items must survive")
    }

    // MARK: - Isolation

    func testDemoServicesNeverTouchTheNetwork() async throws {
        DemoIsolation.shared.setDemoActive(true)
        defer { DemoIsolation.shared.setDemoActive(false) }

        let client = APIClient(baseURL: URL(string: "http://localhost:9")!, vault: TokenVault())
        do {
            let _: Dashboard = try await client.get("/dashboard")
            XCTFail("Production requests must be blocked in demo mode")
        } catch APIError.demoModeNetworkBlocked {
            // expected
        }

        // Demo services keep working while the API client is blocked.
        let store = makeStore()
        let dashboard = await store.dashboard()
        XCTAssertGreaterThan(dashboard.activeLoans, 0)
    }

    func testNotificationDeviceRegistrationIsANoOpInDemo() async throws {
        let service = DemoNotificationService(store: makeStore())
        try await service.registerDevice(apnsToken: "token", environment: "sandbox")
        try await service.unregisterDevice(apnsToken: "token")
    }

    // MARK: - Launch options

    func testLaunchOptionParsing() throws {
        XCTAssertFalse(DemoLaunchOptions.parse(["app"]).isEnabled)

        let parent = DemoLaunchOptions.parse(["app", "-DemoMode"])
        XCTAssertTrue(parent.isEnabled)
        XCTAssertEqual(parent.role, .parent)
        XCTAssertNil(parent.referenceDate)

        let kid = DemoLaunchOptions.parse(["app", "-DemoMode", "-DemoRole", "kid", "-DemoDate", "2025-03-14"])
        XCTAssertTrue(kid.isEnabled)
        XCTAssertEqual(kid.role, .child)
        let fixed = try XCTUnwrap(kid.referenceDate)
        XCTAssertEqual(CalendarDate(fixed, timeZone: DemoMath.calendar.timeZone), try CalendarDate(string: "2025-03-14"))
    }

    func testFixedDemoDateProducesIdenticalContent() async throws {
        let fixed = try CalendarDate(string: "2025-03-14").date(in: DemoMath.calendar.timeZone)
        let first = DemoStore(referenceDate: fixed)
        let second = DemoStore(referenceDate: fixed)
        let a = await first.dashboard()
        let b = await second.dashboard()
        XCTAssertEqual(a, b)
        let firstLoans = await first.loanSummaries(status: nil, childId: nil)
        let secondLoans = await second.loanSummaries(status: nil, childId: nil)
        XCTAssertEqual(firstLoans, secondLoans)
    }

    // MARK: - Math

    func testScheduleWithoutInterestSplitsThePrincipalExactly() {
        let rows = DemoMath.schedule(principal: 100, annualRate: 0, interestEnabled: false, frequency: .monthly, installmentCount: 3, firstDueDate: CalendarDate(year: 2025, month: 1, day: 31))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + $1.amountDue }, 100)
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + $1.interestDue }, 0)
        // Month-end dates clamp instead of drifting.
        XCTAssertEqual(rows[1].dueDate, CalendarDate(year: 2025, month: 2, day: 28))
        XCTAssertEqual(rows[2].dueDate, CalendarDate(year: 2025, month: 3, day: 31))
    }

    func testScheduleWithInterestRepaysTheFullPrincipal() {
        let rows = DemoMath.schedule(principal: 480, annualRate: Decimal(string: "0.05")!, interestEnabled: true, frequency: .monthly, installmentCount: 6, firstDueDate: CalendarDate(year: 2025, month: 1, day: 10))
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.reduce(Decimal(0)) { $0 + $1.principalDue }, 480)
        // 5% APR over six monthly payments on $480 lands near $7 of interest. The bounds guard the
        // rate convention: the annual rate is a fraction (0.05), never a percentage (5).
        let interest = rows.reduce(Decimal(0)) { $0 + $1.interestDue }
        XCTAssertGreaterThan(interest, 6)
        XCTAssertLessThan(interest, 9)
    }

    func testLateFeeCombinesTheFlatAndPercentComponents() {
        // Matches `DueStatus.LateFee`: flat + percent * remaining, both additive.
        XCTAssertEqual(DemoMath.lateFeeAmount(flat: 5, percent: nil, base: 100), 5)
        XCTAssertEqual(DemoMath.lateFeeAmount(flat: nil, percent: Decimal(string: "0.10")!, base: 100), 10)
        XCTAssertEqual(DemoMath.lateFeeAmount(flat: 5, percent: Decimal(string: "0.10")!, base: 100), 15)
        XCTAssertEqual(DemoMath.lateFeeAmount(flat: nil, percent: nil, base: 100), 0)
    }

    func testPercentLateFeeUsesTheRemainingBalance() async throws {
        let store = makeStore()
        let loans = DemoLoanService(store: store)
        let family = await store.family()
        let childId = try XCTUnwrap(family.children.first?.id)
        // Due three weeks ago with a one-day grace period, so the first installment is already late.
        let firstDue = CalendarDate(reference.addingTimeInterval(-21 * 86_400))
        let input = LoanTermsInput(childId: childId, title: "Guitar", principal: 300, interestEnabled: false, annualRate: 0, frequency: .monthly, installmentCount: 3, firstDueDate: firstDue, lateFeeFlat: 2, lateFeePercent: Decimal(string: "0.10")!, lateFeeGraceDays: 1, sendReminders: true, sendReceipts: true)
        let created = try await loans.create(input)
        let detail = try await loans.loan(created.id)
        let fee = try XCTUnwrap(detail.lateFees.first)
        // $2 flat + 10% of the $100 installment that is still fully outstanding.
        XCTAssertEqual(fee.amount, 12)
    }

    func testDueStatusHonorsTheGracePeriod() {
        let due = CalendarDate(year: 2025, month: 5, day: 1)
        XCTAssertEqual(DemoMath.dueStatus(remaining: 10, dueDate: due, today: CalendarDate(year: 2025, month: 4, day: 30), graceDays: 3), .upcoming)
        XCTAssertEqual(DemoMath.dueStatus(remaining: 10, dueDate: due, today: CalendarDate(year: 2025, month: 5, day: 3), graceDays: 3), .due)
        XCTAssertEqual(DemoMath.dueStatus(remaining: 10, dueDate: due, today: CalendarDate(year: 2025, month: 5, day: 5), graceDays: 3), .late)
        XCTAssertEqual(DemoMath.dueStatus(remaining: 0, dueDate: due, today: CalendarDate(year: 2025, month: 6, day: 1), graceDays: 3), .paid)
    }
}
