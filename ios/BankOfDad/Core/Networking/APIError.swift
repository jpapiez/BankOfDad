import Foundation

struct ProblemDetails: Codable, Error, Equatable, Sendable {
    let title: String
    let status: Int
    let detail: String?
    let errors: [String: [String]]?
}

enum APIError: LocalizedError, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case problem(ProblemDetails)
    case unauthorized
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "The server address is invalid."
        case .invalidResponse: return "The server returned an invalid response."
        case .problem(let problem): return problem.detail ?? problem.title
        case .unauthorized: return "Your session expired. Please sign in again."
        case .decoding(let message): return "Could not read the server response: \(message)"
        case .transport(let message): return message
        }
    }
}
