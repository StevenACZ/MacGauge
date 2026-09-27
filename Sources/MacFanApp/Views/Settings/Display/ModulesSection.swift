import SwiftUI

struct ModulesSection: View {
    @ObservedObject var settings: AppSettingsStore
    let simulator: ModulePreviewSimulator

    private struct ModuleToggle: Identifiable {
        let module: SystemModuleKind
        let titleKey: String
        let isOn: Binding<Bool>

        var id: SystemModuleKind { module }
    }

    private var moduleToggles: [ModuleToggle] {
        [
            ModuleToggle(module: .cpu, titleKey: "settings.display.module_cpu", isOn: $settings.showsCPUModule),
            ModuleToggle(module: .memory, titleKey: "settings.display.module_memory", isOn: $settings.showsMemoryModule),
            ModuleToggle(module: .network, titleKey: "settings.display.module_network", isOn: $settings.showsNetworkModule),
        ]
    }

    var body: some View {
        SettingsSurface(icon: "menubar.rectangle", title: "settings.display.menubar_modules".localized) {
            SimulatedPreviewCapsule {
                SimulatedModulesBarPreview(simulator: simulator, settings: settings)
            }

            SettingsDivider()

            SettingsGroupHeader(
                title: "settings.display.modules.visible".localized,
                caption: "settings.display.modules.visible.caption".localized
            )

            HStack(alignment: .top, spacing: 10) {
                ForEach(moduleToggles) { toggle in
                    OptionTile(
                        title: toggle.titleKey.localized,
                        isSelected: toggle.isOn.wrappedValue,
                        action: { toggle.isOn.wrappedValue.toggle() }
                    ) {
                        ModuleSample(module: toggle.module, settings: settings)
                            .opacity(toggle.isOn.wrappedValue ? 1 : 0.35)
                    }
                }
            }

            SettingsDivider()

            SettingsGroupHeader(
                title: "settings.display.modules.spacing".localized,
                caption: "settings.display.modules.spacing.caption".localized
            )

            OptionTilePicker(
                options: ModuleSpacingLevel.allCases,
                selection: $settings.moduleSpacing,
                label: \.localizedName
            ) { level in
                SpacingSample(level: level)
            }
        }
        .animation(Theme.Anim.smooth, value: settings.enabledModules)
    }
}

private struct ModuleSample: View {
    let module: SystemModuleKind
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        switch module {
        case .cpu:
            SamplePercentModule(
                title: "system.cpu".localized,
                style: ModuleColorResolver.previewStyle(for: settings.cpuColorMode, metric: .cpu, settings: settings),
                graphWidth: settings.cpuGraphWidth.width
            )
        case .memory:
            SamplePercentModule(
                title: "system.memory".localized,
                style: ModuleColorResolver.previewStyle(for: settings.memoryColorMode, metric: .memory, settings: settings),
                graphWidth: settings.memoryGraphWidth.width
            )
        case .network:
            let tints = ModuleColorResolver.networkArrowTints(settings: settings)
            NetworkModuleSegment(
                upload: 1_250_000,
                download: 86_000,
                upTint: tints.up,
                downTint: tints.down,
                animated: false
            )
        }
    }
}

private struct SpacingSample: View {
    let level: ModuleSpacingLevel

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 15, height: 9)
            }
        }
        .padding(level == .together ? 3 : 0)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(level == .together ? 0.16 : 0))
        )
    }

    private var gap: CGFloat {
        switch level {
        case .together: return 1.5
        case .tight: return 4
        case .regular: return 7
        case .roomy: return 11
        }
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
