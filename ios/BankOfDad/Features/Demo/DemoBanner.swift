import SwiftUI

/// Persistent "you are in demo mode" affordance shown above every screen while demo mode is active.
/// Tapping it opens the demo controls (switch role, reset data, exit).
struct DemoBanner: View {
    @Environment(AppEnvironment.self) private var environment
    /// Presentation is owned by the host view: a sheet attached inside a `safeAreaInset` does not
    /// reliably present on top of the tab content.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .accessibilityHidden(true)
                Text("Demo mode")
                    .fontWeight(.semibold)
                if let session = environment.demo {
                    Text("· \(session.roleLabel)")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("Options")
                    .font(.footnote.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .overlay(alignment: .bottom) { Divider() }
            // The inset reaches under the status bar; without an explicit shape the whole band
            // (including the untappable status-bar strip) becomes the hit region.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demo.banner")
        .accessibilityLabel("Demo mode. \(environment.demo?.roleLabel ?? "")")
        .accessibilityHint("Opens demo options to switch roles, reset the sample data, or exit the demo.")
    }
}
