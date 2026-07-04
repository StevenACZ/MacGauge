import MacFanCore
import SwiftUI

struct MemoryModuleDetailView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var processes: ProcessStatsMonitor
    let tickSeconds: Double

    private static let tint = Color.indigo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleDetailHeader(icon: "memorychip", title: "system.memory".localized, tint: Self.tint) {
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
                color: Self.tint,
                tickSeconds: tickSeconds
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
                HStack(spacing: 8) {
                    Text("module.memory.pressure".localized)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    PressureBadge(band: pressureBand)
                }
                .font(.callout)
            }

            ModuleCard {
                Text("module.apps.memory".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if processes.topMemoryApps.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("module.apps.collecting".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                } else {
                    ForEach(processes.topMemoryApps) { usage in
                        AppUsageRow(
                            usage: usage,
                            valueText: AppFormatters.memoryAmount(usage.memoryBytes),
                            fraction: Double(usage.memoryBytes) / barScale,
                            tint: Self.tint
                        )
                    }
                }
            }
            .animation(Theme.Anim.content, value: processes.topMemoryApps.map(\.pid))
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

    private var pressureBand: MemoryPressureLevel {
        SystemLoadRules.memoryPressureLevel(
            sysctlLevel: stats.snapshot.memoryPressureSysctlLevel,
            usedPercent: stats.snapshot.memoryPercent
        )
    }
}

extension MemoryPressureLevel {
    var label: String {
        switch self {
        case .normal:
            return "module.memory.pressure.normal".localized
        case .elevated:
            return "module.memory.pressure.elevated".localized
        case .high:
            return "module.memory.pressure.high".localized
        }
    }

    var tint: Color {
        switch self {
        case .normal:
            return .green
        case .elevated:
            return .orange
        case .high:
            return .red
        }
    }
}

private struct PressureBadge: View {
    let band: MemoryPressureLevel

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(band.tint)
                .frame(width: 7, height: 7)
            Text(band.label)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(band.tint.opacity(0.12))
        )
        .animation(Theme.Anim.easeOut, value: band.label)
    }
}
