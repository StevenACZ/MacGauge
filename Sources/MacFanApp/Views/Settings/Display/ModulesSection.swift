import SwiftUI

/// The menu-bar modules card: simulated bar preview, spacing picker, and one
/// visibility toggle per module.
struct ModulesSection: View {
    @ObservedObject var settings: AppSettingsStore
    let simulator: ModulePreviewSimulator

    private struct ModuleToggle: Identifiable {
        let icon: String
        let titleKey: String
        let isOn: Binding<Bool>

        var id: String { titleKey }
    }

    private var moduleToggles: [ModuleToggle] {
        [
            ModuleToggle(icon: "cpu", titleKey: "settings.display.module_cpu", isOn: $settings.showsCPUModule),
            ModuleToggle(icon: "memorychip", titleKey: "settings.display.module_memory", isOn: $settings.showsMemoryModule),
            ModuleToggle(icon: "network", titleKey: "settings.display.module_network", isOn: $settings.showsNetworkModule),
        ]
    }

    var body: some View {
        SettingsSurface(icon: "menubar.rectangle", title: "settings.display.menubar_modules".localized) {
            SimulatedPreviewCapsule {
                SimulatedModulesBarPreview(simulator: simulator, settings: settings)
            }

            SettingsDivider()

            StylePickerRow(
                title: "settings.display.modules.spacing".localized,
                caption: "settings.display.modules.spacing.caption".localized,
                options: ModuleSpacingLevel.allCases,
                label: \.localizedName,
                selection: $settings.moduleSpacing
            )

            ForEach(moduleToggles) { toggle in
                SettingsDivider()

                SettingsToggleRow(
                    title: toggle.titleKey.localized,
                    subtitle: "\(toggle.titleKey).caption".localized,
                    icon: toggle.icon,
                    trailingWidth: 60,
                    isOn: toggle.isOn
                )
            }
        }
        .animation(Theme.Anim.smooth, value: settings.enabledModules)
    }
}

/// All enabled modules side by side with the chosen spacing, approximating
/// how the menu bar lays them out (Together fuses them with hairline gaps).
struct SimulatedModulesBarPreview: View {
    @ObservedObject var simulator: ModulePreviewSimulator
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        let modules = settings.enabledModules
        if modules.isEmpty {
            Label("settings.display.modules.none_hint".localized, systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
        } else {
            HStack(spacing: settings.moduleSpacing == .together ? 2 : 8) {
                ForEach(modules) { module in
                    segment(for: module)
                        .padding(.horizontal, settings.moduleSpacing.padding)
                }
            }
            .frame(height: 22)
            .animation(Theme.Anim.smooth, value: settings.moduleSpacing)
        }
    }

    @ViewBuilder
    private func segment(for module: SystemModuleKind) -> some View {
        switch module {
        case .cpu:
            SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .cpu)
        case .memory:
            SimulatedPercentModulePreview(simulator: simulator, settings: settings, metric: .memory)
        case .network:
            SimulatedNetworkModulePreview(simulator: simulator, settings: settings)
        }
    }
}
