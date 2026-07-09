import SwiftUI

/// The temperature-colors card: the draggable band strip plus one row per
/// band with a numeric threshold field and color presets.
struct TemperatureBandsSection: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        SettingsSurface(icon: "thermometer.medium", title: "settings.display.bands.title".localized) {
            Text("settings.display.bands.caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            BandsStripEditor(
                normalUpper: thresholds.normalUpper,
                hotLower: thresholds.hotLower,
                normalColor: Color(hexString: settings.normalColorHex),
                mediumColor: Color(hexString: settings.mediumColorHex),
                hotColor: Color(hexString: settings.hotColorHex)
            )
            .padding(.vertical, 4)

            SettingsDivider()

            VisualThresholdRow(
                title: "settings.display.normal".localized,
                thresholdLabel: "settings.display.up_to".localized,
                value: thresholds.normalUpper,
                colorHex: settings.colorHexBinding(\.normalColorHex)
            )

            SettingsDivider()

            VisualBandRow(
                title: "settings.display.medium".localized,
                rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) °C",
                colorHex: settings.colorHexBinding(\.mediumColorHex)
            )

            SettingsDivider()

            VisualThresholdRow(
                title: "settings.display.hot".localized,
                thresholdLabel: "settings.display.from".localized,
                value: thresholds.hotLower,
                colorHex: settings.colorHexBinding(\.hotColorHex)
            )
        }
    }

    private var thresholds: (normalUpper: Binding<Double>, hotLower: Binding<Double>) {
        settings.orderedThresholdBindings(
            normalUpper: \.normalUpperCelsius,
            hotLower: \.hotLowerCelsius,
            floor: 20,
            ceiling: 95,
            gap: 5
        )
    }
}
