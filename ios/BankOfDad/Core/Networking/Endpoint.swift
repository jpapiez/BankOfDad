import Foundation

struct APIEndpoint<Response: Decodable> {
    let method: String
    let path: String
    let queryItems: [URLQueryItem]
    let body: Encodable?
    let requiresAuth: Bool

    init(method: String, path: String, queryItems: [URLQueryItem] = [], body: Encodable? = nil, requiresAuth: Bool = true) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
        self.requiresAuth = requiresAuth
    }
}

struct EmptyResponse: Decodable, Sendable {}

struct AnyEncodable: Encodable {
    private let encodeClosure: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { self.encodeClosure = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeClosure(encoder) }
}
