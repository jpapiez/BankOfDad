import SwiftUI

/// A named avatar color. The API stores the hex value; only the name is ever shown.
struct AvatarColorOption: Identifiable, Hashable, Sendable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum AvatarPalette {
    static let options: [AvatarColorOption] = [
        .init(name: "Blue", hex: "#4F8EF7"),
        .init(name: "Orange", hex: "#FF9F1C"),
        .init(name: "Teal", hex: "#2EC4B6"),
        .init(name: "Red", hex: "#E71D36"),
        .init(name: "Purple", hex: "#7B61FF"),
        .init(name: "Green", hex: "#2A9D4B"),
        .init(name: "Pink", hex: "#F15BB5"),
        .init(name: "Yellow", hex: "#FFC43D"),
    ]

    static let defaultHex = options[0].hex

    /// The palette entry for a stored color, or nil for legacy/custom colors.
    static func option(for hex: String?) -> AvatarColorOption? {
        guard let hex else { return nil }
        return options.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }
    }
}

/// A live avatar preview above a grid of named color swatches. Place it inside a `Form`.
struct AvatarColorPicker: View {
    let name: String
    @Binding var selection: String?
    @ScaledMetric(relativeTo: .body) private var swatchSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var columnWidth: CGFloat = 64

    var body: some View {
        Section("Avatar color") {
            HStack(spacing: 16) {
                AvatarView(name: name, colorHex: selection, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name.isEmpty ? "New child" : name).font(.headline)
                    Text(selectionName).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Avatar preview")
            .accessibilityValue(selectionName)
            .accessibilityIdentifier("avatarColor.preview")

            LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth), spacing: 8)], spacing: 16) {
                ForEach(AvatarPalette.options) { option in swatch(option) }
            }
            .padding(.vertical, 8)
        }
    }

    private var selectionName: String {
        if let option = AvatarPalette.option(for: selection) { return option.name }
        return selection == nil ? "No color chosen" : "Custom color"
    }

    private func swatch(_ option: AvatarColorOption) -> some View {
        let isSelected = AvatarPalette.option(for: selection) == option
        return Button { selection = option.hex } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: option.hex) ?? .blue)
                    .frame(width: swatchSize, height: swatchSize)
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: swatchSize * 0.45, weight: .bold))
                                .foregroundStyle(Color.isLight(hex: option.hex) ? .black : .white)
                        }
                    }
                    .padding(4)
                    .overlay(Circle().strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2))
                Text(option.name)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("avatarColor.\(option.name)")
    }
}

#Preview {
    @Previewable @State var selection: String? = AvatarPalette.defaultHex
    Form { AvatarColorPicker(name: "Sam Smith", selection: $selection) }
}
