import Foundation

enum PairingCode {
    static func normalized(_ input: String) -> String {
        input.filter { $0.isLetter || $0.isNumber }.uppercased()
    }

    static func display(_ code: String) -> String {
        let normalized = normalized(code)
        guard normalized.count > 3 else { return normalized }
        let first = normalized.prefix(3)
        let remaining = normalized.dropFirst(3)
        if remaining.count <= 3 { return "\(first)-\(remaining)" }
        return "\(first)-\(remaining.prefix(3))-\(remaining.dropFirst(3))"
    }
}
