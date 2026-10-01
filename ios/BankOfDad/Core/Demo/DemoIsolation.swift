import Foundation

/// Process-wide guard that makes demo mode structurally incapable of touching the production API.
///
/// The demo services never hold an `APIClient`, so this is a second line of defense: while demo mode is
/// active `APIClient` refuses to build a request and push registration is skipped. It is deliberately a
/// plain value rather than a type check, so production code asks "is demo active?" instead of
/// "is this service a demo type?".
final class DemoIsolation: @unchecked Sendable {
    static let shared = DemoIsolation()

    private let lock = NSLock()
    private var active = false

    var isDemoActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return active
    }

    func setDemoActive(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        active = value
    }
}
