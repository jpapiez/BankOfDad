import Foundation
import Observation

/// Live state for an active demo exploration: which role is being explored and which sample child the
/// kid experience is bound to. Created by `AppEnvironment.enterDemo(role:)` and torn down on exit.
@MainActor
@Observable
final class DemoSession {
    let store: DemoStore
    private(set) var role: Role
    private(set) var children: [DemoChild] = []
    private(set) var activeChildId: UUID?

    init(store: DemoStore, role: Role) {
        self.store = store
        self.role = role
    }

    var activeChild: DemoChild? {
        guard let activeChildId else { return children.first }
        return children.first { $0.id == activeChildId } ?? children.first
    }

    /// Short label shown in the persistent demo banner.
    var roleLabel: String {
        role == .parent ? "Parent view" : "\(activeChild?.displayName ?? "Kid") view"
    }

    func refresh() async {
        children = await store.children()
        if activeChildId == nil { activeChildId = children.first?.id }
    }

    func apply(role: Role, childId: UUID?) async {
        self.role = role
        if role == .child { activeChildId = childId ?? activeChildId ?? children.first?.id }
        await store.setRole(role, childId: activeChildId)
        await refresh()
    }

    func currentUser() async -> UserDto {
        if role == .child, let childId = activeChildId, let user = await store.childUser(childId) { return user }
        return await store.parentUser()
    }
}
