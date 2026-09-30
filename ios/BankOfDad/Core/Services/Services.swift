import Foundation

struct FamilyService: Sendable {
    let api: APIClient

    func family() async throws -> FamilyDto { try await api.get("/family") }
    func updateFamily(name: String?, timeZone: String?) async throws -> FamilyDto { try await api.patch("/family", body: UpdateFamilyRequest(name: name, timeZone: timeZone)) }
    func addChild(displayName: String, avatarColor: String?) async throws -> ChildDto { try await api.post("/family/children", body: ChildRequest(displayName: displayName, avatarColor: avatarColor)) }
    func updateChild(_ childId: UUID, displayName: String?, avatarColor: String?) async throws -> ChildDto { try await api.patch("/family/children/\(childId.uuidString)", body: ChildRequest(displayName: displayName, avatarColor: avatarColor)) }
    func pairingCode(childId: UUID) async throws -> PairingCodeResponse { try await api.post("/family/children/\(childId.uuidString)/pairing-code") }
    func revokeDevices(childId: UUID) async throws { try await api.delete("/family/children/\(childId.uuidString)/devices") }
    func invite(email: String?) async throws -> InviteResponse { try await api.post("/family/invites", body: InviteRequest(email: email)) }
}

struct LoanService: Sendable {
    let api: APIClient

    func dashboard() async throws -> Dashboard { try await api.get("/dashboard") }
    func preview(_ input: LoanTermsInput) async throws -> SchedulePreview { try await api.post("/loans/preview", body: input) }
    func create(_ input: LoanTermsInput) async throws -> LoanDetail { try await api.post("/loans", body: input) }
    func parentLoans(status: LoanStatus? = nil, childId: UUID? = nil) async throws -> [LoanSummary] {
        var query: [URLQueryItem] = []
        if let status, status != .unknown { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let childId { query.append(URLQueryItem(name: "childId", value: childId.uuidString)) }
        return try await api.get("/loans", queryItems: query)
    }
    func loan(_ id: UUID) async throws -> LoanDetail { try await api.get("/loans/\(id.uuidString)") }
    func updateLoan(_ id: UUID, title: String? = nil, sendReminders: Bool? = nil, sendReceipts: Bool? = nil) async throws -> LoanDetail {
        try await api.patch("/loans/\(id.uuidString)", body: UpdateLoanRequest(title: title, sendReminders: sendReminders, sendReceipts: sendReceipts))
    }
    func updateInstallment(loanId: UUID, installmentId: UUID, dueDate: CalendarDate) async throws -> LoanDetail {
        try await api.patch("/loans/\(loanId.uuidString)/installments/\(installmentId.uuidString)", body: UpdateInstallmentRequest(dueDate: dueDate))
    }
    func cancel(_ id: UUID) async throws -> LoanDetail { try await api.post("/loans/\(id.uuidString)/cancel") }
    func recordPayment(loanId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> Payment {
        try await api.post("/loans/\(loanId.uuidString)/payments", body: PaymentRequest(amount: amount, paidOn: paidOn, note: note?.isEmpty == true ? nil : note))
    }
    func payments(loanId: UUID) async throws -> [Payment] { try await api.get("/loans/\(loanId.uuidString)/payments") }
    func waiveFee(loanId: UUID, lateFeeId: UUID) async throws -> LoanDetail { try await api.post("/loans/\(loanId.uuidString)/late-fees/\(lateFeeId.uuidString)/waive") }
    func myLoans() async throws -> [LoanSummary] { try await api.get("/me/loans") }
    func myLoan(_ id: UUID) async throws -> LoanDetail { try await api.get("/me/loans/\(id.uuidString)") }
}

struct BillService: Sendable {
    let api: APIClient

    func bills(status: BillStatus? = nil, childId: UUID? = nil) async throws -> [BillSummary] {
        var query: [URLQueryItem] = []
        if let status, status != .unknown { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let childId { query.append(URLQueryItem(name: "childId", value: childId.uuidString)) }
        return try await api.get("/bills", queryItems: query)
    }
    func bill(_ id: UUID) async throws -> BillDetail { try await api.get("/bills/\(id.uuidString)") }
    func create(_ input: BillInput) async throws -> BillDetail { try await api.post("/bills", body: input) }
    func update(_ id: UUID, title: String? = nil, amount: Decimal? = nil, sendReminders: Bool? = nil, sendReceipts: Bool? = nil) async throws -> BillDetail {
        try await api.patch("/bills/\(id.uuidString)", body: UpdateBillRequest(title: title, amount: amount, sendReminders: sendReminders, sendReceipts: sendReceipts))
    }
    func end(_ id: UUID) async throws -> BillDetail { try await api.post("/bills/\(id.uuidString)/end") }
    func recordPayment(billId: UUID, amount: Decimal, paidOn: CalendarDate, note: String?) async throws -> BillPayment {
        try await api.post("/bills/\(billId.uuidString)/payments", body: PaymentRequest(amount: amount, paidOn: paidOn, note: note?.isEmpty == true ? nil : note))
    }
    func waiveFee(billId: UUID, lateFeeId: UUID) async throws -> BillDetail { try await api.post("/bills/\(billId.uuidString)/late-fees/\(lateFeeId.uuidString)/waive") }
}

struct NotificationService: Sendable {
    let api: APIClient

    func notifications(unreadOnly: Bool = false) async throws -> [AppNotification] {
        try await api.get("/notifications", queryItems: [URLQueryItem(name: "unreadOnly", value: unreadOnly ? "true" : "false")])
    }
    func markRead(_ id: UUID) async throws { try await api.sendNoResponse("POST", path: "/notifications/\(id.uuidString)/read") }
    func markAllRead() async throws { try await api.sendNoResponse("POST", path: "/notifications/read-all") }
    func registerDevice(apnsToken: String, environment: String) async throws { try await api.sendNoResponse("POST", path: "/devices", body: DeviceRequest(apnsToken: apnsToken, environment: environment)) }
    func unregisterDevice(apnsToken: String) async throws { try await api.delete("/devices/\(apnsToken)") }
}

struct UpdateFamilyRequest: Encodable { let name: String?; let timeZone: String? }
struct ChildRequest: Encodable { let displayName: String?; let avatarColor: String? }
struct InviteRequest: Encodable { let email: String? }
struct UpdateLoanRequest: Encodable { let title: String?; let sendReminders: Bool?; let sendReceipts: Bool? }
struct UpdateBillRequest: Encodable { let title: String?; let amount: Decimal?; let sendReminders: Bool?; let sendReceipts: Bool? }
struct UpdateInstallmentRequest: Encodable { let dueDate: CalendarDate }
struct PaymentRequest: Encodable { let amount: Decimal; let paidOn: CalendarDate; let note: String? }
struct DeviceRequest: Encodable { let apnsToken: String; let environment: String }
