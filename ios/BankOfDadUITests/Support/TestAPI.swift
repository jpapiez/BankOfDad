import Foundation

/// Minimal client the UI test runner uses to seed preconditions directly against the real backend.
/// UI tests drive the feature under test through the app; everything else is set up here.
final class TestAPI {
    struct Failure: Error, CustomStringConvertible {
        let method: String
        let path: String
        let status: Int
        let body: String
        var description: String { "\(method) \(path) -> \(status): \(body)" }
    }

    static let baseURL: URL = {
        let value = ProcessInfo.processInfo.environment["BANKOFDAD_API_URL"] ?? "http://localhost:8080"
        return URL(string: value)!
    }()

    static let password = "Password123!"

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    // MARK: - Transport

    @discardableResult
    func send(_ method: String, _ path: String, body: Any? = nil, token: String? = nil) throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.baseURL)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?, Error?)
        session.dataTask(with: request) { data, response, error in
            result = (data, response, error)
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let error = result.2 { throw error }
        let status = (result.1 as? HTTPURLResponse)?.statusCode ?? -1
        let data = result.0 ?? Data()
        guard (200..<300).contains(status) else {
            throw Failure(method: method, path: path, status: status, body: String(decoding: data, as: UTF8.self))
        }
        return data
    }

    /// Returns the HTTP status for a request (200 for any 2xx), without throwing on 4xx/5xx.
    func status(_ method: String, _ path: String, body: Any? = nil, token: String? = nil) -> Int {
        do { try send(method, path, body: body, token: token); return 200 }
        catch let failure as Failure { return failure.status }
        catch { return -1 }
    }

    func decode<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, body: Any? = nil, token: String? = nil) throws -> T {
        try JSONDecoder().decode(T.self, from: send(method, path, body: body, token: token))
    }

    // MARK: - Seeding helpers

    func registerParent(name: String = "Dad", familyName: String = "UITest Family") throws -> Parent {
        let email = Self.uniqueEmail()
        let auth = try decode(AuthTokens.self, "POST", "/api/v1/auth/register", body: [
            "email": email, "password": Self.password, "displayName": name,
            "familyName": familyName, "timeZone": TimeZone.current.identifier
        ])
        return Parent(email: email, password: Self.password, name: name, familyName: familyName, auth: auth)
    }

    func login(email: String, password: String) throws -> AuthTokens {
        try decode(AuthTokens.self, "POST", "/api/v1/auth/login", body: ["email": email, "password": password])
    }

    func addChild(_ parent: Parent, name: String, color: String = "#4F8EF7") throws -> Child {
        try decode(Child.self, "POST", "/api/v1/family/children", body: ["displayName": name, "avatarColor": color], token: parent.token)
    }

    func family(_ parent: Parent) throws -> FamilyInfo {
        try decode(FamilyInfo.self, "GET", "/api/v1/family", token: parent.token)
    }

    func pairingCode(_ parent: Parent, childId: String) throws -> PairingCode {
        try decode(PairingCode.self, "POST", "/api/v1/family/children/\(childId)/pairing-code", token: parent.token)
    }

    func pair(code: String, deviceName: String = "UITest iPhone") throws -> AuthTokens {
        try decode(AuthTokens.self, "POST", "/api/v1/auth/pair", body: ["code": code, "deviceName": deviceName])
    }

    /// Adds a child and pairs a device for it, returning the child's session.
    func pairedChild(_ parent: Parent, name: String) throws -> (child: Child, auth: AuthTokens) {
        let child = try addChild(parent, name: name)
        let code = try pairingCode(parent, childId: child.id)
        return (child, try pair(code: code.code))
    }

    func invite(_ parent: Parent, email: String? = nil) throws -> Invite {
        var body: [String: Any] = [:]
        if let email { body["email"] = email }
        return try decode(Invite.self, "POST", "/api/v1/family/invites", body: body, token: parent.token)
    }

    func acceptInvite(code: String, email: String = TestAPI.uniqueEmail("coparent"), name: String = "Co-parent") throws -> AuthTokens {
        try decode(AuthTokens.self, "POST", "/api/v1/auth/accept-invite", body: [
            "inviteCode": code, "email": email, "password": Self.password, "displayName": name
        ])
    }

    /// Status code of a refresh-token rotation (401 once the token is revoked).
    func refreshStatus(_ refreshToken: String) -> Int {
        status("POST", "/api/v1/auth/refresh", body: ["refreshToken": refreshToken])
    }

    struct LoanTerms {
        var title: String
        var principal: Decimal = 300
        var interestEnabled = false
        var annualRate: Decimal = 0
        var frequency = "monthly"
        var installmentCount = 3
        var firstDueDate = Date()
        var lateFeeFlat: Decimal?
        var lateFeePercent: Decimal?
        var lateFeeGraceDays = 0
        var sendReminders = true
        var sendReceipts = true
    }

    func createLoan(_ parent: Parent, childId: String, _ terms: LoanTerms) throws -> LoanDetail {
        var body: [String: Any] = [
            "childId": childId, "title": terms.title, "principal": terms.principal as NSDecimalNumber,
            "interestEnabled": terms.interestEnabled, "annualRate": terms.annualRate as NSDecimalNumber,
            "frequency": terms.frequency, "installmentCount": terms.installmentCount,
            "firstDueDate": Self.day(terms.firstDueDate), "lateFeeGraceDays": terms.lateFeeGraceDays,
            "sendReminders": terms.sendReminders, "sendReceipts": terms.sendReceipts
        ]
        if let flat = terms.lateFeeFlat { body["lateFeeFlat"] = flat as NSDecimalNumber }
        if let percent = terms.lateFeePercent { body["lateFeePercent"] = percent as NSDecimalNumber }
        return try decode(LoanDetail.self, "POST", "/api/v1/loans", body: body, token: parent.token)
    }

    func loan(_ parent: Parent, _ loanId: String) throws -> LoanDetail {
        try decode(LoanDetail.self, "GET", "/api/v1/loans/\(loanId)", token: parent.token)
    }

    func loans(_ parent: Parent) throws -> [LoanSummary] {
        try decode([LoanSummary].self, "GET", "/api/v1/loans", token: parent.token)
    }

    @discardableResult
    func recordPayment(_ parent: Parent, loanId: String, amount: Decimal, note: String? = nil) throws -> Data {
        var body: [String: Any] = ["amount": amount as NSDecimalNumber, "paidOn": Self.day(Date())]
        if let note { body["note"] = note }
        return try send("POST", "/api/v1/loans/\(loanId)/payments", body: body, token: parent.token)
    }

    func cancelLoan(_ parent: Parent, loanId: String) throws {
        try send("POST", "/api/v1/loans/\(loanId)/cancel", token: parent.token)
    }

    /// Development-only test hook: moves every installment `days` days earlier.
    @discardableResult
    func backdate(_ parent: Parent, loanId: String, days: Int) throws -> LoanDetail {
        try decode(LoanDetail.self, "POST", "/api/v1/testing/loans/\(loanId)/backdate", body: ["days": days], token: parent.token)
    }

    /// Development-only test hook: runs the reminder / late-fee sweep for the parent's family now.
    func sweep(_ parent: Parent) throws {
        try send("POST", "/api/v1/testing/sweep", token: parent.token)
    }

    func notifications(_ token: String, unreadOnly: Bool = false) throws -> [NotificationItem] {
        try decode([NotificationItem].self, "GET", "/api/v1/notifications?unreadOnly=\(unreadOnly)", token: token)
    }

    // MARK: - Utilities

    static func uniqueEmail(_ prefix: String = "ui") -> String {
        "\(prefix)-\(UUID().uuidString.prefix(12).lowercased())@example.com"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func date(_ day: String) -> Date { dayFormatter.date(from: day)! }
}

// MARK: - DTOs (only the fields the tests need)

struct AuthTokens: Decodable {
    let accessToken: String
    let refreshToken: String
    let user: UserInfo
}

struct UserInfo: Decodable {
    let id: String
    let role: String
    let displayName: String
    let email: String?
}

struct Parent {
    let email: String
    let password: String
    let name: String
    let familyName: String
    let auth: AuthTokens
    var token: String { auth.accessToken }
}

struct Child: Decodable {
    let id: String
    let displayName: String
    let avatarColor: String?
    let pairedDeviceCount: Int
}

struct FamilyInfo: Decodable {
    let id: String
    let name: String
    let timeZone: String
    let parents: [UserInfo]
    let children: [Child]
}

struct PairingCode: Decodable {
    let code: String
    let qrPayload: String
}

struct Invite: Decodable {
    let inviteCode: String
}

struct LoanSummary: Decodable {
    let id: String
    let title: String
    let status: String
}

struct LoanDetail: Decodable {
    struct Installment: Decodable {
        let id: String
        let seq: Int
        let dueDate: String
        let amountDue: Decimal
        let remaining: Decimal
        let status: String
    }
    struct LateFee: Decodable {
        let id: String
        let installmentSeq: Int
        let amount: Decimal
        let waivedAt: String?
    }
    struct Payment: Decodable {
        let amount: Decimal
        let note: String?
    }

    let id: String
    let title: String
    let status: String
    let principal: Decimal
    let balance: Decimal
    let amountPaid: Decimal
    let lateInstallments: Int
    let interestEnabled: Bool
    let annualRate: Decimal
    let frequency: String
    let installmentCount: Int
    let firstDueDate: String
    let lateFeeFlat: Decimal?
    let lateFeePercent: Decimal?
    let lateFeeGraceDays: Int
    let sendReminders: Bool
    let sendReceipts: Bool
    let installments: [Installment]
    let lateFees: [LateFee]
    let payments: [Payment]
}

struct NotificationItem: Decodable {
    let id: String
    let type: String
    let title: String
    let loanId: String?
    let readAt: String?
}
