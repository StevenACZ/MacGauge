import AppKit
import SwiftUI

/// Shared building blocks for the CPU/RAM/network detail popovers.

struct ModuleDetailHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let tint: Color
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: 30, height: 30)

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
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                .fill(Theme.Layout.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous)
                        .strokeBorder(Theme.Layout.cardStroke, lineWidth: 1)
                )
        )
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

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(Theme.Anim.easeOut) {
                justCopied = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
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
