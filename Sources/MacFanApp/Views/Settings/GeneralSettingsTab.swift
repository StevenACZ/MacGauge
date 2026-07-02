import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var loginManager: LaunchAtLoginManager

    let setLaunchAtLogin: (Bool) -> Void

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "gearshape", title: "General") {
                SettingsRow(title: "Temperature") {
                    Picker("Temperature unit", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(title: "Start at login") {
                    Toggle("", isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "Restore on quit") {
                    Toggle("", isOn: $settings.restoreAutomaticOnQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}
