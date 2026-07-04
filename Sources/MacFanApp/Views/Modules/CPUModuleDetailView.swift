import MacFanCore
import SwiftUI

struct CPUModuleDetailView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var processes: ProcessStatsMonitor
    @ObservedObject var settings: AppSettingsStore
    let tickSeconds: Double
    var animated = true

    @State private var isExpanded = false

    /// Same resolution as the menu bar label, so the popover chart always
    /// matches the colors the user configured for the module.
    private var tint: Color {
        ModuleColorResolver.cpuChartColor(percent: stats.snapshot.cpuPercent, settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleDetailHeader(icon: "cpu", title: "system.cpu".localized, tint: tint) {
                ModuleHeaderValue(text: stats.snapshot.cpuPercent.map { AppFormatters.percent($0) } ?? "--%")
            }

            SparklineChart(
                values: stats.cpuHistory,
                capacity: SystemStatsMonitor.historyCapacity,
                peak: 100,
                color: tint,
                tickSeconds: tickSeconds,
                animated: animated
            )
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            ModuleCard {
                ModuleInfoRow(label: "module.cpu.chip".localized, value: SystemInfo.chipName)
                coresRow
                uptimeRow
            }

            ModuleCard {
                Text("module.apps.cpu".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if processes.hasSampledCPU, !processes.topCPUApps.isEmpty {
                    ForEach(processes.topCPUApps.prefix(rowLimit)) { usage in
                        AppUsageRow(
                            usage: usage,
                            valueText: String(format: "%.1f%%", usage.cpuPercent),
                            fraction: usage.cpuPercent / barScale,
                            tint: tint
                        )
                    }
                    if processes.topCPUApps.count > ProcessStatsMonitor.collapsedCount {
                        ShowMoreButton(isExpanded: $isExpanded)
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("module.apps.collecting".localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
                }
            }
            .animation(Theme.Anim.content, value: processes.topCPUApps.map(\.pid))
            .animation(Theme.Anim.content, value: isExpanded)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { processes.start() }
        .onDisappear { processes.stop() }
    }

    private var rowLimit: Int {
        isExpanded ? ProcessStatsMonitor.expandedCount : ProcessStatsMonitor.collapsedCount
    }

    /// Bars are relative to the busiest process (floor of one core) so the
    /// top entry always reads full-ish and the rest scale against it.
    private var barScale: Double {
        max(processes.topCPUApps.first?.cpuPercent ?? 100, 100)
    }

    /// Performance/efficiency split as one square per core, with the plain
    /// total as fallback when the split is unknown.
    private var coresRow: some View {
        HStack(spacing: 8) {
            Text("module.cpu.cores".localized)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let performance = SystemInfo.performanceCoreCount,
                let efficiency = SystemInfo.efficiencyCoreCount
            {
                if performance + efficiency <= 16 {
                    CoreGrid(performanceCount: performance, efficiencyCount: efficiency)
                }
                Text("module.cpu.cores_split".localized(performance, efficiency))
                    .monospacedDigit()
            } else {
                Text("\(SystemInfo.logicalCoreCount)")
                    .monospacedDigit()
            }
        }
        .font(.callout)
        .help(coresHelp)
    }

    private var coresHelp: String {
        let total = SystemInfo.logicalCoreCount
        if let performance = SystemInfo.performanceCoreCount,
            let efficiency = SystemInfo.efficiencyCoreCount
        {
            return "module.cpu.cores_value".localized(total, performance, efficiency)
        }
        return "\(total)"
    }

    private var uptimeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("module.cpu.uptime".localized)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 1) {
                Text(uptimeDurationText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if !bootDateText.isEmpty {
                    Text(bootDateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.callout)
    }

    private var uptimeDurationText: String {
        guard let bootDate = SystemInfo.bootDate else { return "--" }
        let elapsed = max(0, Date().timeIntervalSince(bootDate))
        let days = Int(elapsed) / 86_400
        let hours = (Int(elapsed) % 86_400) / 3_600
        let minutes = (Int(elapsed) % 3_600) / 60

        if days > 0 { return "uptime.days_hours".localized(days, hours) }
        if hours > 0 { return "uptime.hours_minutes".localized(hours, minutes) }
        return "uptime.minutes".localized(minutes)
    }

    private var bootDateText: String {
        guard let bootDate = SystemInfo.bootDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.locale
        return formatter.string(from: bootDate)
    }
}

/// One rounded square per core — performance cores in the accent tint,
/// efficiency cores dimmed — so the P/E split reads at a glance.
private struct CoreGrid: View {
    let performanceCount: Int
    let efficiencyCount: Int

    var body: some View {
        HStack(spacing: 5) {
            coreSquares(count: performanceCount, tint: Theme.accent)
            coreSquares(count: efficiencyCount, tint: Theme.accent.opacity(0.28))
        }
    }

    private func coreSquares(count: Int, tint: Color) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(tint)
                    .frame(width: 5, height: 11)
            }
        }
    }
}
