import SwiftUI

/// Compact menu-bar content for the system modules: a tiny title over the
/// live value, plus a mini sparkline (CPU/RAM) or stacked up/down rates
/// (network). Hit testing stays off so clicks reach the status item button.
/// Every live text sits on a hidden widest-case template so the item keeps a
/// constant width while values change digit count.

struct PercentModuleStatusLabel: View {
    @ObservedObject var stats: SystemStatsMonitor
    let title: String
    let metric: KeyPath<SystemLoadSnapshot, Double?>
    let history: KeyPath<SystemStatsMonitor, [Double]>
    let color: Color
    let tickSeconds: Double

    var body: some View {
        HStack(spacing: 3) {
            VStack(spacing: -1) {
                Text(title)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack {
                    Text(verbatim: "100%")
                        .hidden()
                    Text(stats.snapshot[keyPath: metric].map { "\(Int($0.rounded()))%" } ?? "--%")
                        .contentTransition(.numericText())
                }
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
            }

            SparklineChart(
                values: stats[keyPath: history],
                capacity: SystemStatsMonitor.historyCapacity,
                peak: 100,
                color: color,
                fillOpacity: 0.45,
                lineWidth: 1,
                tickSeconds: tickSeconds
            )
            .frame(width: 26, height: 15)
            .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .fixedSize()
        .allowsHitTesting(false)
    }
}

struct NetworkModuleStatusLabel: View {
    @ObservedObject var stats: SystemStatsMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            rateRow(
                symbol: "arrow.up",
                rate: stats.snapshot.uploadBytesPerSecond,
                tint: .orange
            )
            rateRow(
                symbol: "arrow.down",
                rate: stats.snapshot.downloadBytesPerSecond,
                tint: .blue
            )
        }
        .padding(.horizontal, 3)
        .frame(height: 22)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func rateRow(symbol: String, rate: Double?, tint: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(tint)
            ZStack(alignment: .leading) {
                Text(verbatim: "888 MB/s")
                    .hidden()
                Text(AppFormatters.byteRateCompact(rate))
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, weight: .medium))
            .monospacedDigit()
        }
    }
}
