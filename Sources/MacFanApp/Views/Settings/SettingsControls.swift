import SwiftUI

struct ColorPresetPicker: View {
    @Binding var selection: String

    private var presets: [ColorPreset] {
        [
            ColorPreset(name: "color.white".localized, hex: "#FFFFFF"),
            ColorPreset(name: "color.green".localized, hex: "#30D158"),
            ColorPreset(name: "color.yellow".localized, hex: "#FFD60A"),
            ColorPreset(name: "color.orange".localized, hex: "#FF9500"),
            ColorPreset(name: "color.red".localized, hex: "#FF453A"),
            ColorPreset(name: "color.blue".localized, hex: "#0A84FF"),
        ]
    }

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
            .fill(state.tint)
            .frame(width: 10, height: 10)
            .accessibilityLabel(state.localizedTitle)
    }
}

extension HelperCommandService.HelperState {
    var localizedTitle: String {
        switch self {
        case .ready:
            return "helper.state.authorized".localized
        case .needsApproval:
            return "helper.state.approval_needed".localized
        case .needsAuthorization:
            return "helper.state.not_authorized".localized
        case .unavailable:
            return "helper.state.unavailable".localized
        case .stale:
            return "helper.state.reload_needed".localized
        case .reloading:
            return "helper.state.reloading".localized
        case .failed:
            return "helper.state.failed".localized
        case .unknown:
            return "helper.state.checking".localized
        }
    }

    var tint: Color {
        switch self {
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

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.shield.fill"
        case .needsApproval:
            return "person.badge.shield.checkmark"
        case .needsAuthorization:
            return "lock.shield"
        case .stale, .reloading:
            return "arrow.triangle.2.circlepath"
        case .unavailable, .failed:
            return "exclamationmark.shield.fill"
        case .unknown:
            return "shield"
        }
    }
}

private struct ColorPreset: Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}
