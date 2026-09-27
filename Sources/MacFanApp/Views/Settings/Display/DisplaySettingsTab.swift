import SwiftUI

/// The visual-configuration screen: a section sidebar on the left (fan +
/// temperature, modules, and the CPU/RAM/network charts) and one card at a
/// time on the right. Module previews run on simulated activity so the user
/// watches their colors and thresholds react without loading the Mac.
struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    /// Held plain so the tab never re-renders per monitor tick; only the fan
    /// section's live preview leaf observes the monitor.
    let monitor: FanMonitor

    /// False while another tab is selected so the live previews stop ticking.
    let isActive: Bool

    @State private var section: DisplaySection = .fan
    /// Held as plain @State so only the preview subviews observe its ticks;
    /// the tab itself never re-renders per tick.
    @State private var simulator = ModulePreviewSimulator()

    private enum DisplaySection: String, CaseIterable, Identifiable {
        case fan
        case modules
        case cpu
        case memory
        case network

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .fan: return "fanblades"
            case .modules: return "menubar.rectangle"
            case .cpu: return "cpu"
            case .memory: return "memorychip"
            case .network: return "network"
            }
        }

        var tint: Color {
            switch self {
            case .fan, .cpu: return Theme.accent
            case .modules: return Self.blue
            case .memory: return Self.indigo
            case .network: return Self.orange
            }
        }

        private static let blue = AppearancePalette.lightAdapted(.blue)
        private static let indigo = AppearancePalette.lightAdapted(.indigo)
        private static let orange = AppearancePalette.lightAdapted(.orange)

        var localizedName: String {
            switch self {
            case .fan: return "settings.display.section.fan_temp".localized
            case .modules: return "settings.display.section.modules".localized
            case .cpu: return "system.cpu".localized
            case .memory: return "system.memory".localized
            case .network: return "system.network".localized
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            sectionSidebar

            SettingsPane {
                switch section {
                case .fan:
                    FanMenuBarItemSection(settings: settings, monitor: monitor, isActive: isActive)
                    TemperatureBandsSection(settings: settings)
                case .modules:
                    ModulesSection(settings: settings, simulator: simulator, monitor: monitor, isActive: isActive)
                case .cpu:
                    PercentModuleSection(settings: settings, simulator: simulator, metric: .cpu)
                case .memory:
                    PercentModuleSection(settings: settings, simulator: simulator, metric: .memory)
                case .network:
                    NetworkModuleSection(settings: settings, simulator: simulator)
                }
            }
        }
        .onChange(of: isActive) { _ in updateSimulation() }
        .onChange(of: section) { _ in updateSimulation() }
        .onAppear { updateSimulation() }
        .onDisappear { simulator.setRunning(false) }
    }

    /// The simulator only ticks while a section with module previews is
    /// visible; the fan section reads the real monitor instead.
    private func updateSimulation() {
        simulator.setRunning(isActive && section != .fan)
    }

    // MARK: - Section sidebar

    private var sectionSidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(DisplaySection.allCases) { item in
                sidebarRow(item)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 176)
    }

    private func sidebarRow(_ item: DisplaySection) -> some View {
        let isSelected = section == item
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return Button {
            section = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : item.tint)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? item.tint : item.tint.opacity(0.14))
                    )
                Text(item.localizedName)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(6)
            .contentShape(shape)
            .background(shape.fill(isSelected ? Color.primary.opacity(0.07) : Color.clear))
            .overlay(shape.strokeBorder(isSelected ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.Anim.hover, value: isSelected)
        .accessibilityLabel(item.localizedName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
