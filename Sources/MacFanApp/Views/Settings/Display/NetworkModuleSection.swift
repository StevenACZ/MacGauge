import SwiftUI

/// The network module card: simulated preview, color mode, and per-direction
/// arrow colors when multicolor is on.
struct NetworkModuleSection: View {
    @ObservedObject var settings: AppSettingsStore
    let simulator: ModulePreviewSimulator

    var body: some View {
        SettingsSurface(icon: "network", title: "settings.display.module_network".localized) {
            SimulatedPreviewCapsule {
                SimulatedNetworkModulePreview(simulator: simulator, settings: settings)
            }

            HiddenModuleHint(isShown: settings.showsNetworkModule)

            SettingsDivider()

            metricRows
        }
        .animation(Theme.Anim.smooth, value: settings.networkColorMode)
    }

    @ViewBuilder
    private var metricRows: some View {
        StylePickerRow(
            title: "settings.display.modules.color".localized,
            caption: "settings.display.modules.color.caption.network".localized,
            options: [.multicolor, .mono, .gray],
            label: \.localizedName,
            selection: $settings.networkColorMode
        )

        if settings.networkColorMode == .multicolor {
            SettingsDivider()

            NetworkColorRow(
                title: "settings.display.network.upload_color".localized,
                symbol: "arrow.up",
                colorHex: settings.colorHexBinding(\.networkUpColorHex)
            )

            SettingsDivider()

            NetworkColorRow(
                title: "settings.display.network.download_color".localized,
                symbol: "arrow.down",
                colorHex: settings.colorHexBinding(\.networkDownColorHex)
            )
        }
    }
}

private struct NetworkColorRow: View {
    let title: String
    let symbol: String
    @Binding var colorHex: String

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.callout.weight(.semibold))

            Spacer()

            ColorPresetPicker(selection: $colorHex)
        }
        .padding(.vertical, 2)
    }
}

struct SimulatedNetworkModulePreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tints = ModuleColorResolver.networkArrowTints(settings: settings)
        NetworkModuleSegment(
            upload: simulator.uploadBytesPerSecond,
            download: simulator.downloadBytesPerSecond,
            upTint: tints.up,
            downTint: tints.down,
            animated: settings.performanceMode == .full && !reduceMotion
        )
        .frame(height: 22)
    }
}
