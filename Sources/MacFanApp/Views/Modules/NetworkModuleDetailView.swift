import SwiftUI

struct NetworkModuleDetailView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var info: NetworkInfoMonitor
    @ObservedObject var settings: AppSettingsStore
    let tickSeconds: Double
    var animated = true

    /// Same resolution as the menu bar label, so the popover always matches
    /// the arrow colors the user configured for the module.
    private var tints: (up: Color, down: Color) {
        ModuleColorResolver.networkArrowTints(settings: settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleDetailHeader(icon: "network", title: "system.network".localized, tint: tints.down) {
                VStack(alignment: .trailing, spacing: 1) {
                    rateLine(
                        symbol: "arrow.down",
                        text: AppFormatters.byteRate(stats.snapshot.downloadBytesPerSecond),
                        tint: tints.down
                    )
                    rateLine(
                        symbol: "arrow.up",
                        text: AppFormatters.byteRate(stats.snapshot.uploadBytesPerSecond),
                        tint: tints.up
                    )
                }
            }

            ZStack {
                SparklineChart(
                    values: stats.downloadHistory,
                    capacity: SystemStatsMonitor.historyCapacity,
                    peak: chartPeak,
                    color: tints.down,
                    tickSeconds: tickSeconds,
                    animated: animated
                )
                SparklineChart(
                    values: stats.uploadHistory,
                    capacity: SystemStatsMonitor.historyCapacity,
                    peak: chartPeak,
                    color: tints.up,
                    fillOpacity: 0.22,
                    tickSeconds: tickSeconds,
                    animated: animated
                )
            }
            .frame(height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            ModuleCard {
                ModuleInfoRow(label: "module.network.interface".localized, value: interfaceText)
                ModuleInfoRow(
                    label: "module.network.local_ip".localized,
                    value: info.localIPAddress ?? "--",
                    isCopyable: info.localIPAddress != nil
                )
                publicIPRow
                ModuleInfoRow(
                    label: "module.network.router".localized,
                    value: info.routerAddress ?? "--",
                    isCopyable: info.routerAddress != nil
                )
            }

            ModuleCard {
                Text("module.network.session".localized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    sessionTotal(
                        symbol: "arrow.down",
                        text: AppFormatters.memoryAmount(stats.snapshot.sessionReceivedBytes),
                        tint: tints.down
                    )
                    sessionTotal(
                        symbol: "arrow.up",
                        text: AppFormatters.memoryAmount(stats.snapshot.sessionSentBytes),
                        tint: tints.up
                    )
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    private var publicIPRow: some View {
        HStack(spacing: 8) {
            Text("module.network.public_ip".localized)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if info.isFetchingPublicIP {
                ProgressView()
                    .controlSize(.mini)
            } else if let publicIP = info.publicIPAddress {
                Text(publicIP)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.middle)
                CopyIconButton(value: publicIP)
            } else {
                Text(info.publicIPFetchFailed ? "module.network.fetch_error".localized : "--")
                    .foregroundStyle(.secondary)
            }
            Button {
                info.fetchPublicIP()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(info.isFetchingPublicIP)
            .help("module.network.refresh_public_ip".localized)
            .accessibilityLabel("module.network.refresh_public_ip".localized)
        }
        .font(.callout)
    }

    private func rateLine(symbol: String, text: String, tint: Color) -> some View {
        ArrowRateText(symbol: symbol, text: text, tint: tint, font: .callout.weight(.semibold))
    }

    private func sessionTotal(symbol: String, text: String, tint: Color) -> some View {
        ArrowRateText(symbol: symbol, text: text, tint: tint, font: .callout)
    }

    private var interfaceText: String {
        switch (info.interfaceDisplayName, info.interfaceBSDName) {
        case (let display?, let bsd?):
            return "\(display) (\(bsd))"
        case (let display?, nil):
            return display
        case (nil, let bsd?):
            return bsd
        case (nil, nil):
            return "--"
        }
    }

    private var chartPeak: Double {
        let highest = max(stats.downloadHistory.max() ?? 0, stats.uploadHistory.max() ?? 0)
        return max(1_048_576, highest)
    }
}

/// One arrow + value line, shared by the header rates and session totals.
private struct ArrowRateText: View {
    let symbol: String
    let text: String
    let tint: Color
    let font: Font

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(font)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
