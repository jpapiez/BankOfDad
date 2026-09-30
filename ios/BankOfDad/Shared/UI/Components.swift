import SwiftUI

struct LoadingView: View {
    var message: String = "Loading…"
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("Error: \(message)")
            .accessibilityIdentifier("errorBanner")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

struct MoneyText: View {
    let value: Decimal
    var currencyCode: String = "USD"
    var font: Font = .body

    var body: some View {
        Text(AppFormatters.money(value, currencyCode: currencyCode))
            .font(font)
            .monospacedDigit()
    }
}

struct StatusChip: View {
    let text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
            .accessibilityLabel(text)
    }
}

struct ProgressRing: View {
    let progress: Double
    var color: Color = Theme.bankAccent

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.weight(.bold))
        }
        .frame(width: 58, height: 58)
        .accessibilityLabel("Progress \(Int(progress * 100)) percent")
    }
}

struct AvatarView: View {
    let name: String
    let colorHex: String?
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(Color.isLight(hex: colorHex) ? .black : .white)
            .frame(width: size, height: size)
            .background(Color(hex: colorHex) ?? .blue, in: Circle())
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xff) / 255
        let green = Double((value >> 8) & 0xff) / 255
        let blue = Double(value & 0xff) / 255
        self.init(red: red, green: green, blue: blue)
    }

    /// True for light colors (e.g. orange, teal, yellow), where dark text has far better contrast than white.
    /// The cutoff keeps white on colors where it still meets 3:1 for bold text.
    static func isLight(hex: String?) -> Bool {
        guard let hex else { return false }
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6, let value = UInt64(trimmed, radix: 16) else { return false }
        func linear(_ channel: UInt64) -> Double {
            let c = Double(channel & 0xff) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(value >> 16) + 0.7152 * linear(value >> 8) + 0.0722 * linear(value)
        return luminance > 0.4
    }
}

struct Card<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}
