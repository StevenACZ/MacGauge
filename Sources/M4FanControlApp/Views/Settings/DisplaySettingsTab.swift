import SwiftUI

struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "paintpalette", title: "Display") {
                SettingsRow(title: "Animate fan icon") {
                    Toggle("", isOn: $settings.animateFanIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                visualThresholdRow(
                    title: "Normal",
                    thresholdLabel: "Up to",
                    value: $settings.normalUpperCelsius,
                    colorHex: colorHexBinding(\.normalColorHex)
                )

                SettingsDivider()

                visualBandRow(
                    title: "Medium",
                    rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) C",
                    colorHex: colorHexBinding(\.mediumColorHex)
                )

                SettingsDivider()

                visualThresholdRow(
                    title: "Hot",
                    thresholdLabel: "From",
                    value: $settings.hotLowerCelsius,
                    colorHex: colorHexBinding(\.hotColorHex)
                )
            }
        }
    }

    private func colorHexBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<String> {
        Binding {
            settings[keyPath: keyPath]
        } set: { hex in
            settings[keyPath: keyPath] = hex
        }
    }

    private func visualThresholdRow(
        title: String,
        thresholdLabel: String,
        value: Binding<Double>,
        colorHex: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(thresholdLabel)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Text("C")
                .foregroundStyle(.secondary)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    private func visualBandRow(title: String, rangeText: String, colorHex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(rangeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }
}
