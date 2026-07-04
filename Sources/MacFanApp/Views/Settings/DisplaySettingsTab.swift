import SwiftUI

struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "paintpalette", title: "settings.display.title".localized) {
                SettingsRow(title: "settings.display.animate_icon".localized) {
                    Toggle("", isOn: $settings.animateFanIcon)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                visualThresholdRow(
                    title: "settings.display.normal".localized,
                    thresholdLabel: "settings.display.up_to".localized,
                    value: $settings.normalUpperCelsius,
                    colorHex: colorHexBinding(\.normalColorHex)
                )

                SettingsDivider()

                visualBandRow(
                    title: "settings.display.medium".localized,
                    rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) C",
                    colorHex: colorHexBinding(\.mediumColorHex)
                )

                SettingsDivider()

                visualThresholdRow(
                    title: "settings.display.hot".localized,
                    thresholdLabel: "settings.display.from".localized,
                    value: $settings.hotLowerCelsius,
                    colorHex: colorHexBinding(\.hotColorHex)
                )
            }

            SettingsSurface(icon: "menubar.rectangle", title: "settings.display.menubar_modules".localized) {
                SettingsRow(title: "settings.display.module_cpu".localized) {
                    Toggle("", isOn: $settings.showsCPUModule)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "settings.display.module_memory".localized) {
                    Toggle("", isOn: $settings.showsMemoryModule)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "settings.display.module_network".localized) {
                    Toggle("", isOn: $settings.showsNetworkModule)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                Text("settings.display.modules_hint".localized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
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
