import SwiftUI

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var loginManager: LaunchAtLoginManager
    @ObservedObject private var localization = LocalizationManager.shared

    let setLaunchAtLogin: (Bool) -> Void

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "gearshape", title: "settings.general.title".localized) {
                SettingsRow(title: "settings.general.temperature".localized, icon: "thermometer.medium") {
                    Picker("settings.general.temperature_unit".localized, selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                SettingsDivider()

                SettingsRow(title: "settings.general.language".localized, icon: "globe") {
                    Picker("settings.general.language".localized, selection: $localization.language) {
                        Text("English").tag("en")
                        Text("Español").tag("es")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                SettingsDivider()

                performanceModeSection

                SettingsDivider()

                SettingsToggleRow(
                    title: "settings.general.launch_at_login".localized,
                    subtitle: "settings.general.launch_at_login.caption".localized,
                    icon: "power",
                    isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { setLaunchAtLogin($0) }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "settings.general.restore_on_quit".localized,
                    subtitle: "settings.general.restore_on_quit.caption".localized,
                    icon: "arrow.uturn.backward.circle",
                    isOn: $settings.restoreAutomaticOnQuit
                )
            }
        }
    }

    private var performanceModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, alignment: .center)
                Text("settings.general.performance".localized)
                    .font(.callout.weight(.semibold))
            }

            HStack(spacing: 10) {
                ForEach(PerformanceMode.allCases) { mode in
                    PerformanceModeCard(
                        mode: mode,
                        isSelected: settings.performanceMode == mode
                    ) {
                        settings.performanceMode = mode
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One selectable performance-mode card: icon, name, and a one-line promise,
/// so the choice reads at a glance instead of as a bare segmented control.
private struct PerformanceModeCard: View {
    let mode: PerformanceMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: mode.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconTint)
                    Text(mode.localizedName)
                        .font(.callout.weight(.semibold))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.5))
                }

                Text(mode.localizedCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.65) : Color.primary.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.hover, value: isSelected)
        .accessibilityLabel(mode.localizedName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconTint: Color {
        switch mode {
        case .efficient: return .green
        case .full: return .yellow
        }
    }
}
