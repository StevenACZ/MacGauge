import SwiftUI

struct NetworkModuleDetailView: View {
    @ObservedObject var stats: SystemStatsMonitor
    @ObservedObject var info: NetworkInfoMonitor
    let tickSeconds: Double
    var animated = true

    private static let downloadTint = Color.blue
    private static let uploadTint = Color.orange

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModuleDetailHeader(icon: "network", title: "system.network".localized, tint: Self.downloadTint) {
                VStack(alignment: .trailing, spacing: 1) {
                    rateLine(
                        symbol: "arrow.down",
                        text: AppFormatters.byteRate(stats.snapshot.downloadBytesPerSecond),
                        tint: Self.downloadTint
                    )
                    rateLine(
                        symbol: "arrow.up",
                        text: AppFormatters.byteRate(stats.snapshot.uploadBytesPerSecond),
                        tint: Self.uploadTint
                    )
                }
            }

            ZStack {
                SparklineChart(
                    values: stats.downloadHistory,
                    capacity: SystemStatsMonitor.historyCapacity,
                    peak: chartPeak,
                    color: Self.downloadTint,
                    tickSeconds: tickSeconds,
                    animated: animated
                )
                SparklineChart(
                    values: stats.uploadHistory,
                    capacity: SystemStatsMonitor.historyCapacity,
                    peak: chartPeak,
                    color: Self.uploadTint,
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
                        tint: Self.downloadTint
                    )
                    sessionTotal(
                        symbol: "arrow.up",
                        text: AppFormatters.memoryAmount(stats.snapshot.sessionSentBytes),
                        tint: Self.uploadTint
                    )
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { info.refresh() }
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
        }
        .font(.callout)
    }

    private func rateLine(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private func sessionTotal(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
            Text(text)
                .font(.callout)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
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
