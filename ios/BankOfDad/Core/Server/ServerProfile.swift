import Foundation
import Darwin

struct ServerProfile: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let origin: URL
    let familyName: String?
    let capabilities: ServerCapabilities
    let childPin: ChildPinPolicy

    init(id: UUID, origin: URL, familyName: String?, capabilities: ServerCapabilities, childPin: ChildPinPolicy) {
        self.id = id
        self.origin = origin
        self.familyName = familyName
        self.capabilities = capabilities
        self.childPin = childPin
    }

    init(descriptor: ServerDescriptor) throws {
        let origin = try ServerOriginPolicy.validate(descriptor.origin)
        id = descriptor.serverId
        self.origin = origin
        familyName = descriptor.familyName
        capabilities = descriptor.capabilities
        childPin = descriptor.childPin
    }
}

struct ServerDescriptor: Codable, Equatable, Sendable {
    let protocolVersion: Int
    let serverId: UUID
    let origin: String
    let setupState: String
    let familyName: String?
    let capabilities: ServerCapabilities
    let childPin: ChildPinPolicy
}

struct ServerCapabilities: Codable, Equatable, Hashable, Sendable {
    let parentPassword: Bool
    let childPassword: Bool
    let childPin: Bool
    let apple: Bool
    let push: Bool

    static let legacy = ServerCapabilities(parentPassword: true, childPassword: false, childPin: false, apple: true, push: true)
}

struct ChildPinPolicy: Codable, Equatable, Hashable, Sendable {
    let minimumLength: Int
    let maximumLength: Int

    static let standard = ChildPinPolicy(minimumLength: 6, maximumLength: 12)
}

enum EnrollmentKind: String, Codable, Sendable {
    case bootstrap
    case parent
    case child
}

struct EnrollmentPreview: Codable, Equatable, Sendable {
    let kind: EnrollmentKind
    let familyName: String?
    let childName: String?
    let email: String?
    let expiresAt: Date
}

struct ServerConnectionLink: Equatable, Sendable {
    static let protocolVersion = 1

    let origin: URL
    let serverID: UUID
    let kind: EnrollmentKind
    let token: String

    init(scannedValue: String) throws {
        guard let url = URL(string: scannedValue),
              url.scheme?.lowercased() == "bankofdad",
              url.host?.lowercased() == "connect",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryValue("v") == String(Self.protocolVersion),
              let originValue = components.queryValue("origin"),
              let serverValue = components.queryValue("server"),
              let serverID = UUID(uuidString: serverValue),
              let kindValue = components.queryValue("kind"),
              let kind = EnrollmentKind(rawValue: kindValue),
              let token = components.queryValue("token"),
              token.count >= 32 else {
            throw ServerConnectionError.invalidLink
        }
        origin = try ServerOriginPolicy.validate(originValue)
        self.serverID = serverID
        self.kind = kind
        self.token = token
    }
}

enum ServerOriginPolicy {
    static func validate(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty,
              let host = components.host,
              !host.isEmpty,
              let origin = components.url else {
            throw ServerConnectionError.invalidOrigin
        }
        if scheme == "http" && !isPrivateHost(host) {
            throw ServerConnectionError.publicHTTPNotAllowed
        }
        return origin
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let value = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if value == "localhost" || value.hasSuffix(".local") { return true }
        if isPrivateIPv6Literal(value) { return true }
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 ||
            parts[0] == 127 ||
            (parts[0] == 169 && parts[1] == 254) ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168)
    }

    private static func isPrivateIPv6Literal(_ value: String) -> Bool {
        var address = in6_addr()
        let parsed = value.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return false }

        let bytes = withUnsafeBytes(of: address) { Array($0) }
        guard bytes.count == 16 else { return false }

        let isLoopback = bytes.dropLast().allSatisfy { $0 == 0 } && bytes[15] == 1
        let isUniqueLocal = (bytes[0] & 0xfe) == 0xfc
        let isLinkLocal = bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
        return isLoopback || isUniqueLocal || isLinkLocal
    }
}

struct ServerDiscoveryClient: Sendable {
    private let session: URLSession
    private let decoder = APIClient.makeDecoder()
    private let encoder = APIClient.makeEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func discover(origin: URL, expectedServerID: UUID? = nil) async throws -> ServerDescriptor {
        let url = origin.appending(path: ".well-known/bankofdad")
        let descriptor: ServerDescriptor = try await request(url: url)
        guard descriptor.protocolVersion == ServerConnectionLink.protocolVersion else {
            throw ServerConnectionError.unsupportedProtocol
        }
        let canonicalOrigin = try ServerOriginPolicy.validate(descriptor.origin)
        guard canonicalOrigin == origin else { throw ServerConnectionError.originMismatch }
        if let expectedServerID, descriptor.serverId != expectedServerID {
            throw ServerConnectionError.serverIdentityMismatch
        }
        return descriptor
    }

    func inspect(link: ServerConnectionLink) async throws -> (ServerDescriptor, EnrollmentPreview) {
        let descriptor = try await discover(origin: link.origin, expectedServerID: link.serverID)
        let endpoint = APIClient.makeURL(baseURL: link.origin, path: "/enrollment/inspect", queryItems: [])
        guard let endpoint else { throw ServerConnectionError.invalidOrigin }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(EnrollmentInspectRequest(token: link.token))
        let preview: EnrollmentPreview = try await self.request(request)
        guard preview.kind == link.kind else { throw ServerConnectionError.enrollmentMismatch }
        return (descriptor, preview)
    }

    private func request<Response: Decodable>(url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await self.request(request)
    }

    private func request<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ServerConnectionError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ServerConnectionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw try APIClient.error(from: data, statusCode: http.statusCode, decoder: decoder)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ServerConnectionError.invalidResponse
        }
    }
}

enum ServerConnectionError: LocalizedError {
    case invalidLink
    case invalidOrigin
    case publicHTTPNotAllowed
    case unsupportedProtocol
    case originMismatch
    case serverIdentityMismatch
    case enrollmentMismatch
    case invalidResponse
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case .invalidLink: "This is not a valid Bank of Dad connection code."
        case .invalidOrigin: "The server address is invalid."
        case .publicHTTPNotAllowed: "Public servers must use HTTPS. Plain HTTP is allowed only on a private network."
        case .unsupportedProtocol: "This server uses an unsupported Bank of Dad connection protocol."
        case .originMismatch: "The server reported a different address than the one you scanned."
        case .serverIdentityMismatch: "The server identity does not match the connection code."
        case .enrollmentMismatch: "The invitation role does not match the connection code."
        case .invalidResponse: "The server returned an invalid response."
        case .unreachable(let message): "The server could not be reached. \(message)"
        }
    }
}

private extension URLComponents {
    func queryValue(_ name: String) -> String? {
        queryItems?.first(where: { $0.name == name })?.value
    }
}
