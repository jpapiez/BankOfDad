import Foundation

/// What `GET /api/v1/version` returns.
struct ServerVersion: Codable, Equatable, Sendable {
    let version: String
    let commit: String
    let apiLevel: Int
    let minClientApiLevel: Int
}

/// The API contract this build of the app speaks. Bump `apiLevel` when the app starts relying on a new or
/// changed server route/field; bump `minServerApiLevel` to the first server level that supports it.
enum ClientVersion {
    static let apiLevel = 2
    static let minServerApiLevel = 1

    static var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    static var display: String { "\(appVersion) (\(build))" }
}

enum VersionCompatibility: Equatable, Sendable {
    case compatible
    case appTooOld
    case serverTooOld
    /// The server answered 404 for `/version`, so it was built before version reporting existed.
    case serverPredatesVersioning

    static func evaluate(server: ServerVersion, clientApiLevel: Int = ClientVersion.apiLevel, minServerApiLevel: Int = ClientVersion.minServerApiLevel) -> VersionCompatibility {
        if clientApiLevel < server.minClientApiLevel { return .appTooOld }
        if server.apiLevel < minServerApiLevel { return .serverTooOld }
        return .compatible
    }

    var isProblem: Bool { self != .compatible }

    var message: String {
        switch self {
        case .compatible: return "App and server are compatible."
        case .appTooOld: return "This app is older than the server supports. Update the app."
        case .serverTooOld: return "The server is older than this app expects. Update the server."
        case .serverPredatesVersioning: return "The server predates version reporting, so it is probably out of date. Update the server."
        }
    }
}
