import SwiftUI

struct ColorPresetPicker: View {
    @Binding var selection: String

    private let presets = [
        ColorPreset(name: "White", hex: "#FFFFFF"),
        ColorPreset(name: "Green", hex: "#30D158"),
        ColorPreset(name: "Yellow", hex: "#FFD60A"),
        ColorPreset(name: "Red", hex: "#FF453A"),
    ]

    var body: some View {
        HStack(spacing: 9) {
            ForEach(presets) { preset in
                Button {
                    selection = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hexString: preset.hex))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .strokeBorder(borderColor(for: preset), lineWidth: selectionMatches(preset) ? 3 : 1)
                        )
                        .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
            }
        }
    }

    private func selectionMatches(_ preset: ColorPreset) -> Bool {
        selection.uppercased() == preset.hex
    }

    private func borderColor(for preset: ColorPreset) -> Color {
        if selectionMatches(preset) {
            return .accentColor
        }
        return preset.hex == "#FFFFFF" ? .secondary : .clear
    }
}

struct HelperStatusBadge: View {
    let state: HelperCommandService.HelperState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityLabel(title)
    }

    private var title: String {
        switch state {
        case .ready:
            return "Authorized"
        case .needsApproval:
            return "Approval needed"
        case .needsAuthorization:
            return "Not authorized"
        case .unavailable:
            return "Unavailable"
        case .stale:
            return "Reload needed"
        case .reloading:
            return "Reloading"
        case .failed:
            return "Failed"
        case .unknown:
            return "Checking"
        }
    }

    private var color: Color {
        switch state {
        case .ready:
            return .green
        case .needsApproval:
            return .yellow
        case .needsAuthorization, .unknown:
            return .secondary
        case .stale:
            return .orange
        case .reloading:
            return .blue
        case .unavailable, .failed:
            return .red
        }
    }
}

private struct ColorPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}
