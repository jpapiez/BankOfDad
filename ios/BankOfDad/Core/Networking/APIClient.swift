import Foundation

actor TokenVault {
    private var accessToken: String?
    private var refreshToken: String?

    func tokens() -> (access: String?, refresh: String?) { (accessToken, refreshToken) }

    func update(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    func clear() { update(accessToken: nil, refreshToken: nil) }
}

actor RefreshCoordinator {
    private var refreshTask: Task<AuthResponse, Error>?

    func refreshIfNeeded(baseURL: URL, vault: TokenVault, session: URLSession, decoder: JSONDecoder, encoder: JSONEncoder) async throws -> AuthResponse {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<AuthResponse, Error> {
            let tokens = await vault.tokens()
            guard let refreshToken = tokens.refresh else { throw APIError.unauthorized }
            let url = APIClient.makeURL(baseURL: baseURL, path: "/auth/refresh", queryItems: [])
            guard let url else { throw APIError.invalidURL }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try encoder.encode(["refreshToken": refreshToken])
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw try APIClient.error(from: data, statusCode: http.statusCode, decoder: decoder) }
            let auth = try decoder.decode(AuthResponse.self, from: data)
            await vault.update(accessToken: auth.accessToken, refreshToken: auth.refreshToken)
            return auth
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }
}

final class APIClient: @unchecked Sendable {
    let baseURL: URL
    let vault: TokenVault
    private let urlSession: URLSession
    private let refreshCoordinator = RefreshCoordinator()
    private let onAuthFailed: () async -> Void
    private let onTokensRefreshed: (AuthResponse) async -> Void

    let decoder: JSONDecoder
    let encoder: JSONEncoder

    init(baseURL: URL, vault: TokenVault, urlSession: URLSession = .shared, onAuthFailed: @escaping () async -> Void = {}, onTokensRefreshed: @escaping (AuthResponse) async -> Void = { _ in }) {
        self.baseURL = baseURL
        self.vault = vault
        self.urlSession = urlSession
        self.onAuthFailed = onAuthFailed
        self.onTokensRefreshed = onTokensRefreshed
        self.decoder = APIClient.makeDecoder()
        self.encoder = APIClient.makeEncoder()
    }

    func get<Response: Decodable>(_ path: String, queryItems: [URLQueryItem] = [], requiresAuth: Bool = true) async throws -> Response {
        try await send(APIEndpoint<Response>(method: "GET", path: path, queryItems: queryItems, requiresAuth: requiresAuth))
    }

    func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, requiresAuth: Bool = true) async throws -> Response {
        try await send(APIEndpoint<Response>(method: "POST", path: path, body: body, requiresAuth: requiresAuth))
    }

    func post<Response: Decodable>(_ path: String, requiresAuth: Bool = true) async throws -> Response {
        try await send(APIEndpoint<Response>(method: "POST", path: path, requiresAuth: requiresAuth))
    }

    func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        try await send(APIEndpoint<Response>(method: "PATCH", path: path, body: body))
    }

    func delete(_ path: String) async throws {
        let _: EmptyResponse = try await send(APIEndpoint<EmptyResponse>(method: "DELETE", path: path))
    }

    func sendNoResponse(_ method: String, path: String, requiresAuth: Bool = true) async throws {
        let endpoint = APIEndpoint<EmptyResponse>(method: method, path: path, requiresAuth: requiresAuth)
        let _: EmptyResponse = try await send(endpoint)
    }

    func sendNoResponse<Body: Encodable>(_ method: String, path: String, body: Body, requiresAuth: Bool = true) async throws {
        let endpoint = APIEndpoint<EmptyResponse>(method: method, path: path, body: body, requiresAuth: requiresAuth)
        let _: EmptyResponse = try await send(endpoint)
    }

    func send<Response: Decodable>(_ endpoint: APIEndpoint<Response>) async throws -> Response {
        do { return try await perform(endpoint, retryingAfterRefresh: true) }
        catch APIError.unauthorized {
            await onAuthFailed()
            throw APIError.unauthorized
        }
    }

    func buildRequest<Response: Decodable>(for endpoint: APIEndpoint<Response>) async throws -> URLRequest {
        guard let url = APIClient.makeURL(baseURL: baseURL, path: endpoint.path, queryItems: endpoint.queryItems) else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }
        let tokens = await vault.tokens()
        if endpoint.requiresAuth, let token = tokens.access {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Response: Decodable>(_ endpoint: APIEndpoint<Response>, retryingAfterRefresh: Bool) async throws -> Response {
        let request = try await buildRequest(for: endpoint)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await urlSession.data(for: request) }
        catch { throw APIError.transport(error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401, endpoint.requiresAuth, retryingAfterRefresh {
            let auth: AuthResponse
            do {
                auth = try await refreshCoordinator.refreshIfNeeded(baseURL: baseURL, vault: vault, session: urlSession, decoder: decoder, encoder: encoder)
            } catch let error as URLError {
                throw APIError.transport(error.localizedDescription)
            } catch {
                await vault.clear()
                throw APIError.unauthorized
            }
            await onTokensRefreshed(auth)
            return try await perform(endpoint, retryingAfterRefresh: false)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw try APIClient.error(from: data, statusCode: http.statusCode, decoder: decoder)
        }
        if let empty = EmptyResponse() as? Response {
            return empty
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error.localizedDescription) }
    }

    static func makeURL(baseURL: URL, path: String, queryItems: [URLQueryItem]) -> URL? {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let full = trimmedPath == "health" ? "\(trimmedBase)/health" : "\(trimmedBase)/api/v1/\(trimmedPath)"
        var components = URLComponents(string: full)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        return components?.url
    }

    static func error(from data: Data, statusCode: Int, decoder: JSONDecoder) throws -> APIError {
        if let problem = try? decoder.decode(ProblemDetails.self, from: data) { return .problem(problem) }
        if statusCode == 401 { return .unauthorized }
        return .problem(ProblemDetails(title: HTTPURLResponse.localizedString(forStatusCode: statusCode), status: statusCode, detail: nil, errors: nil))
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateParsers.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(string)")
        }
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601DateParsers.fractional.string(from: date))
        }
        return encoder
    }
}

enum ISO8601DateParsers {
    static func date(from string: String) -> Date? {
        fractional.date(from: string) ?? standard.date(from: string) ?? normalizedFractionalDate(from: string)
    }

    private static func normalizedFractionalDate(from string: String) -> Date? {
        guard let dot = string.firstIndex(of: ".") else { return nil }
        let fractionStart = string.index(after: dot)
        guard let timeZoneStart = string[fractionStart...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else { return nil }
        let fraction = String(string[fractionStart..<timeZoneStart])
        guard !fraction.isEmpty else { return nil }
        let normalized = fraction.count >= 3 ? String(fraction.prefix(3)) : fraction.padding(toLength: 3, withPad: "0", startingAt: 0)
        return fractional.date(from: String(string[..<fractionStart]) + normalized + String(string[timeZoneStart...]))
    }

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
