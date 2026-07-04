import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var loginManager: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared

    let setLaunchAtLogin: (Bool) -> Void

    init(
        settings: AppSettingsStore,
        loginManager: LaunchAtLoginManager,
        setLaunchAtLogin: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.loginManager = loginManager
        self.setLaunchAtLogin = setLaunchAtLogin
    }

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "gearshape", title: "settings.general.title".localized) {
                SettingsRow(title: "settings.general.temperature".localized) {
                    Picker("settings.general.temperature_unit".localized, selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(title: "settings.general.language".localized) {
                    Picker("settings.general.language".localized, selection: $localization.language) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                SettingsDivider()

                SettingsRow(
                    title: "settings.general.performance".localized,
                    subtitle: "settings.general.performance.caption".localized
                ) {
                    Picker("settings.general.performance".localized, selection: $settings.performanceMode) {
                        ForEach(PerformanceMode.allCases) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(
                    title: "settings.general.launch_at_login".localized,
                    subtitle: "settings.general.launch_at_login.caption".localized
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { loginManager.isEnabled },
                            set: { setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(
                    title: "settings.general.restore_on_quit".localized,
                    subtitle: "settings.general.restore_on_quit.caption".localized
                ) {
                    Toggle("", isOn: $settings.restoreAutomaticOnQuit)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }
}
