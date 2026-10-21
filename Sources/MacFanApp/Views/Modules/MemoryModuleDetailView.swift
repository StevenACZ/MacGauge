import MacFanCore
import SwiftUI

struct MemoryModuleDetailView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var processes: ProcessStatsMonitor
    @ObservedObject var settings: AppSettingsStore
    let tickSeconds: Double
    var animated = true

    @State private var isExpanded = false

    /// Same resolution as the menu bar label, so the popover chart always
    /// matches the colors the user configured for the module.
    private var tint: Color {
        ModuleColorResolver.memoryChartColor(
            percent: stats.snapshot.memoryPercent,
            settings: settings,
            adaptsToWindowBackground: true
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleDetailHeader(icon: "memorychip", title: "system.memory".localized, tint: tint) {
                VStack(alignment: .trailing, spacing: 0) {
                    ModuleHeaderValue(text: stats.snapshot.memoryPercent.map { AppFormatters.percent($0) } ?? "--%")
                    Text(
                        "module.memory.of_total".localized(
                            AppFormatters.gigabytes(stats.snapshot.memoryUsedBytes),
                            AppFormatters.gigabytes(stats.snapshot.memoryTotalBytes)
                        )
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }

            SparklineChart(
                values: stats.memoryHistory,
                capacity: SystemStatsMonitor.historyCapacity,
                peak: 100,
                color: tint,
                tickSeconds: tickSeconds,
                animated: animated,
                adaptsToWindowBackground: true
            )
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            ModuleCard {
                ModuleInfoRow(
                    label: "module.memory.used".localized,
                    value: AppFormatters.gigabytes(stats.snapshot.memoryUsedBytes)
                )
                ModuleInfoRow(
                    label: "module.memory.free".localized,
                    value: AppFormatters.gigabytes(availableBytes)
                )
            }

            TopAppsCard(
                title: "module.apps.memory".localized,
                apps: processes.topMemoryApps,
                valueText: { AppFormatters.memoryAmount($0.memoryBytes) },
                fraction: { Double($0.memoryBytes) / barScale },
                tint: tint,
                isExpanded: $isExpanded
            )
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private var availableBytes: UInt64? {
        guard let used = stats.snapshot.memoryUsedBytes else { return nil }
        let total = stats.snapshot.memoryTotalBytes
        return total > used ? total - used : 0
    }

    private var barScale: Double {
        Double(max(processes.topMemoryApps.first?.memoryBytes ?? 1, 1))
    }
}
