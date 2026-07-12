import SwiftUI

/// Update lifecycle row for the popover footer: pending update → one-click
/// install with inline download/install progress; a failed install offers a
/// retry. Hidden entirely while no update is pending.
struct UpdateMenuRow: View {
    @ObservedObject var manager: UpdateManager

    var body: some View {
        switch manager.phase {
        case .idle:
            EmptyView()

        case .available(let version):
            UpdateActionRow(
                icon: "arrow.down.circle",
                title: "popover.update_available".localized,
                subtitle: "popover.update_install_hint".localized(version)
            ) {
                manager.installPendingUpdate()
            }

        case .downloading(let fraction):
            UpdateProgressRow(
                title: "popover.update_downloading".localized,
                subtitle: fraction.map { "\(Int($0 * 100))%" },
                fraction: fraction
            )

        case .installing:
            UpdateProgressRow(
                title: "popover.update_installing".localized,
                subtitle: "popover.update_relaunch".localized,
                fraction: nil
            )

        case .failed:
            UpdateActionRow(
                icon: "exclamationmark.arrow.circlepath",
                title: "popover.update_failed".localized,
                subtitle: "popover.update_retry_hint".localized
            ) {
                manager.installPendingUpdate()
            }
        }
    }
}

/// ActionRow variant with a caption subtitle, used only by the update row.
private struct UpdateActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.callout)
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Layout.rowRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Anim.easeOut) {
                isHovered = hovering
            }
        }
    }
}

/// Non-interactive progress row shown while an update downloads or installs.
private struct UpdateProgressRow: View {
    let title: String
    let subtitle: String?
    let fraction: Double?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.circular)
                } else {
                    ProgressView()
                }
            }
            .controlSize(.small)
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}
