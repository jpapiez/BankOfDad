import XCTest
@testable import BankOfDad

final class DTOTests: XCTestCase {
    func testAuthResponseDecodes() throws {
        let json = Data(#"""
        { "accessToken": "access", "refreshToken": "refresh", "expiresAt": "2026-09-27T22:15:00Z", "user": { "id": "00000000-0000-0000-0000-000000000001", "familyId": "00000000-0000-0000-0000-000000000002", "role": "parent", "displayName": "Dad", "email": "dad@example.com" } }
        """#.utf8)
        let response = try APIClient.makeDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(response.accessToken, "access")
        XCTAssertEqual(response.user.role, .parent)
        XCTAssertEqual(response.user.email, "dad@example.com")
    }

    func testLoanDetailDecodesAndUnknownEnumFallsBack() throws {
        let json = Data(#"""
        { "id": "30000000-0000-0000-0000-000000000001", "title": "New bike", "childId": "10000000-0000-0000-0000-000000000001", "childName": "Sam", "principal": 300.00, "status": "mystery", "balance": 203.10, "amountPaid": 101.46, "nextDueDate": "2027-01-01", "nextAmountDue": 50.73, "lateInstallments": 0, "createdAt": "2026-09-27T22:00:00Z", "interestEnabled": true, "annualRate": 0.05, "frequency": "monthly", "installmentCount": 6, "firstDueDate": "2026-11-01", "lateFeeFlat": 5.00, "lateFeePercent": 0.10, "lateFeeGraceDays": 3, "sendReminders": true, "sendReceipts": true, "totalInterest": 4.38, "totalRepayable": 304.38, "outstandingFees": 0.00, "installments": [ { "id": "40000000-0000-0000-0000-000000000001", "seq": 1, "dueDate": "2026-11-01", "principalDue": 49.48, "interestDue": 1.25, "amountDue": 50.73, "principalPaid": 49.48, "interestPaid": 1.25, "remaining": 0.00, "status": "paid" } ], "payments": [], "lateFees": [], "termsSummary": "Sam borrowed $300.00." }
        """#.utf8)
        let detail = try APIClient.makeDecoder().decode(LoanDetail.self, from: json)
        XCTAssertEqual(detail.status, .unknown)
        XCTAssertEqual(detail.installments.first?.status, .paid)
        XCTAssertEqual(detail.nextDueDate?.description, "2027-01-01")
    }

    func testNotificationDecodes() throws {
        let json = Data(#"""
        { "id": "50000000-0000-0000-0000-000000000001", "type": "receipt", "title": "Payment received", "body": "Nice work", "loanId": "30000000-0000-0000-0000-000000000001", "createdAt": "2026-09-27T22:00:00.1234567Z", "readAt": null }
        """#.utf8)
        let notification = try APIClient.makeDecoder().decode(AppNotification.self, from: json)
        XCTAssertEqual(notification.type, .receipt)
        XCTAssertNil(notification.readAt)
    }
}
