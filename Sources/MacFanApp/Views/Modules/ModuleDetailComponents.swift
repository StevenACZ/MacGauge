import AppKit
import SwiftUI

/// Shared building blocks for the CPU/RAM/network detail popovers.

/// Tinted circle with a symbol (or a small spinner while busy), shared by the
/// popover header, module detail headers, and the helper status card.
struct TintedIconCircle: View {
    let icon: String
    let tint: Color
    let size: CGFloat
    let iconSize: CGFloat
    var isBusy = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.15))
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .font(.system(size: iconSize, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct ModuleDetailHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            TintedIconCircle(icon: icon, tint: tint, size: 30, iconSize: 14)

            Text(title)
                .font(.headline)

            Spacer(minLength: 0)

            trailing()
        }
    }
}

struct ModuleCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(
            radius: Theme.Layout.cardRadius,
            fill: Theme.Layout.cardFill,
            stroke: Theme.Layout.cardStroke
        )
    }
}

/// The "top apps" card shared by the CPU and RAM popovers: caption header,
/// a measuring state until sampling lands, then rows plus show-more.
struct TopAppsCard: View {
    let title: String
    let apps: [AppResourceUsage]
    var hasSampled = true
    let valueText: (AppResourceUsage) -> String
    let fraction: (AppResourceUsage) -> Double
    let tint: Color
    @Binding var isExpanded: Bool

    var body: some View {
        ModuleCard {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if hasSampled, !apps.isEmpty {
                ForEach(apps.prefix(rowLimit)) { usage in
                    AppUsageRow(
                        usage: usage,
                        valueText: valueText(usage),
                        fraction: fraction(usage),
                        tint: tint
                    )
                }
                if apps.count > ProcessStatsMonitor.collapsedCount {
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
        .animation(Theme.Anim.content, value: apps.map(\.pid))
        .animation(Theme.Anim.content, value: isExpanded)
    }

    private var rowLimit: Int {
        isExpanded ? ProcessStatsMonitor.expandedCount : ProcessStatsMonitor.collapsedCount
    }
}

struct ModuleInfoRow: View {
    let label: String
    let value: String
    var isCopyable = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.numericText())
            if isCopyable, !value.isEmpty {
                CopyIconButton(value: value)
            }
        }
        .font(.callout)
    }
}

/// Small copy-to-pasteboard button that flashes a green checkmark.
struct CopyIconButton: View {
    let value: String

    @State private var justCopied = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(Theme.Anim.easeOut) {
                justCopied = true
            }
            resetTask?.cancel()
            resetTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(Theme.Anim.easeOut) {
                    justCopied = false
                }
            }
        } label: {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(.caption2)
                .foregroundStyle(justCopied ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("module.copy".localized)
        .accessibilityLabel("module.copy".localized)
    }
}

/// One app row inside the "top apps" list: icon, name, animated usage bar,
/// and the formatted value.
struct AppUsageRow: View {
    let usage: AppResourceUsage
    let valueText: String
    let fraction: Double
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            if let icon = usage.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 13))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(usage.name)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(valueText)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                UsageBar(fraction: fraction, tint: tint)
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.75))
                    .frame(width: max(3, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 4)
        .animation(Theme.Anim.content, value: fraction)
    }
}

/// Expands the top-processes list from the compact five to the full set the
/// monitor keeps; the popover grows with the content.
struct ShowMoreButton: View {
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "module.apps.show_less".localized : "module.apps.show_more".localized)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

/// Big current value shown at the right of a module header.
struct ModuleHeaderValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
