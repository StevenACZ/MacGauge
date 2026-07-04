import MacFanCore
import SwiftUI

/// Compact menu-bar content for the system modules. Each module is its own
/// independent status item; the labels observe the settings store so the
/// spacing, graph-length, and color-style choices apply live. Hit testing
/// stays off so clicks reach the status item button. Every live text sits on
/// a hidden widest-case template so items keep a constant width while values
/// change digit count.

struct PercentModuleStatusLabel: View {
    enum Metric {
        case cpu
        case memory
    }

    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var settings: AppSettingsStore
    let metric: Metric

    var body: some View {
        PercentModuleSegment(
            title: title,
            percent: percent,
            history: history,
            color: chartColor,
            graphWidth: graphWidth.width,
            tickSeconds: settings.controlTickSeconds,
            animated: settings.performanceMode == .full
        )
        .padding(.horizontal, settings.moduleSpacing.padding)
        .frame(height: 22)
        .fixedSize()
        .animation(Theme.Anim.smooth, value: settings.moduleSpacing)
        .animation(Theme.Anim.smooth, value: graphWidth)
        .allowsHitTesting(false)
    }

    private var title: String {
        metric == .cpu ? "system.cpu".localized : "system.memory".localized
    }

    private var percent: Double? {
        metric == .cpu ? stats.snapshot.cpuPercent : stats.snapshot.memoryPercent
    }

    private var history: [Double] {
        metric == .cpu ? stats.cpuHistory : stats.memoryHistory
    }

    private var graphWidth: ModuleGraphWidth {
        metric == .cpu ? settings.cpuGraphWidth : settings.memoryGraphWidth
    }

    private var chartColor: Color {
        switch metric {
        case .cpu:
            return ModuleColorResolver.cpuChartColor(percent: stats.snapshot.cpuPercent, settings: settings)
        case .memory:
            return ModuleColorResolver.memoryChartColor(percent: stats.snapshot.memoryPercent, settings: settings)
        }
    }
}

struct ModuleSegmentFramesKey: PreferenceKey {
    static let defaultValue: [SystemModuleKind: CGRect] = [:]

    static func reduce(value: inout [SystemModuleKind: CGRect], nextValue: () -> [SystemModuleKind: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

/// All enabled modules fused into one status item (Together spacing): the
/// same per-module labels laid side by side with a hairline gap, so even the
/// system's own gap between separate items disappears. Each segment reports
/// its frame so the controller routes clicks to the right detail popover.
struct FusedModulesStatusLabel: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var settings: AppSettingsStore
    let modules: [SystemModuleKind]

    private static let coordinateSpace = "fused-modules"

    var body: some View {
        HStack(spacing: 2) {
            ForEach(modules) { module in
                segment(for: module)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ModuleSegmentFramesKey.self,
                                value: [module: proxy.frame(in: .named(Self.coordinateSpace))]
                            )
                        }
                    )
            }
        }
        .padding(.horizontal, 2)
        .fixedSize()
        .coordinateSpace(name: Self.coordinateSpace)
    }

    @ViewBuilder
    private func segment(for module: SystemModuleKind) -> some View {
        switch module {
        case .cpu:
            PercentModuleStatusLabel(stats: stats, settings: settings, metric: .cpu)
        case .memory:
            PercentModuleStatusLabel(stats: stats, settings: settings, metric: .memory)
        case .network:
            NetworkModuleStatusLabel(stats: stats, settings: settings)
        }
    }
}

struct NetworkModuleStatusLabel: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        NetworkModuleSegment(
            upload: stats.snapshot.uploadBytesPerSecond,
            download: stats.snapshot.downloadBytesPerSecond,
            upTint: arrowTints.up,
            downTint: arrowTints.down,
            animated: settings.performanceMode == .full
        )
        .padding(.horizontal, settings.moduleSpacing.padding)
        .frame(height: 22)
        .fixedSize()
        .animation(Theme.Anim.smooth, value: settings.moduleSpacing)
        .allowsHitTesting(false)
    }

    private var arrowTints: (up: Color, down: Color) {
        ModuleColorResolver.networkArrowTints(settings: settings)
    }
}

/// Also reused by the Settings > Display previews with simulated values.
struct PercentModuleSegment: View {
    let title: String
    let percent: Double?
    let history: [Double]
    let color: Color
    let graphWidth: CGFloat
    let tickSeconds: Double
    let animated: Bool

    var body: some View {
        HStack(spacing: 3) {
            VStack(spacing: -1) {
                Text(title)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack {
                    Text(verbatim: "100%")
                        .hidden()
                    Text(percent.map { "\(Int($0.rounded()))%" } ?? "--%")
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .animation(animated ? Theme.Anim.smooth : nil, value: percent.map { Int($0.rounded()) })
            }

            SparklineChart(
                values: history,
                capacity: SystemStatsMonitor.historyCapacity,
                peak: 100,
                color: color,
                fillOpacity: 0.45,
                lineWidth: 1,
                tickSeconds: tickSeconds,
                animated: animated
            )
            .frame(width: graphWidth, height: 15)
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            .animation(Theme.Anim.smooth, value: color)
        }
        .fixedSize()
    }
}

/// Also reused by the Settings > Display previews with simulated values.
struct NetworkModuleSegment: View {
    let upload: Double?
    let download: Double?
    let upTint: Color
    let downTint: Color
    let animated: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rateRow(symbol: "arrow.up", rate: upload, tint: upTint)
            rateRow(symbol: "arrow.down", rate: download, tint: downTint)
        }
        .fixedSize()
    }

    private func rateRow(symbol: String, rate: Double?, tint: Color) -> some View {
        // Idle arrows dim so a glance shows which direction is moving data.
        let isActive = (rate ?? 0) >= 1_024
        return HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(tint)
                .opacity(isActive ? 1 : 0.4)
                .animation(animated ? Theme.Anim.smooth : nil, value: isActive)
                .animation(animated ? Theme.Anim.smooth : nil, value: tint)
            ZStack(alignment: .leading) {
                Text(verbatim: "888 MB/s")
                    .hidden()
                Text(AppFormatters.byteRateCompact(rate))
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, weight: .medium))
            .monospacedDigit()
            .animation(animated ? Theme.Anim.smooth : nil, value: AppFormatters.byteRateCompact(rate))
        }
    }
}
