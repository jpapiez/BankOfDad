import SwiftUI

enum Theme {
    static let bankAccent = Color.green
    static let kidAccent = Color.orange
    static let softBackground = Color(.secondarySystemGroupedBackground)
    static let cardBackground = Color(.systemBackground)

    static func tint(for role: Role?) -> Color { role == .child ? kidAccent : bankAccent }
}
