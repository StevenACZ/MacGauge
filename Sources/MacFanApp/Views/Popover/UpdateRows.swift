import SwiftUI

/// Update lifecycle card shown under the popover header: a pending update
/// downloads in one click, a downloaded update offers install now or later,
/// and a failed install offers a retry. Hidden while no update is pending.
struct UpdateCard: View {
    @ObservedObject var manager: UpdateManager

    var body: some View {
        content
            .animation(Theme.Anim.mode, value: manager.phase)
    }

    @ViewBuilder
    private var content: some View {
        switch manager.phase {
        case .idle:
            EmptyView()

        case .available(let version):
            card(
                icon: "arrow.down.circle.fill",
                title: "update.card.available".localized(version),
                subtitle: "update.card.available.hint".localized
            ) {
                UpdateCardButton(title: "update.card.action.update".localized) {
                    manager.installPendingUpdate()
                }
            }

        case .downloading(let fraction):
            card(
                icon: "arrow.down.circle",
                title: versioned("update.card.downloading", fallback: "update.card.downloading.unknown"),
                subtitle: nil
            ) {
                HStack(spacing: 8) {
                    Group {
                        if let fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                        }
                    }
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)

                    if let fraction {
                        Text("update.card.percent".localized(Int(fraction * 100)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .readyToInstall(let version):
            card(
                icon: "checkmark.circle.fill",
                title: versioned("update.card.ready", version: version, fallback: "update.card.ready.unknown"),
                subtitle: "update.card.ready.hint".localized
            ) {
                HStack(spacing: 8) {
                    UpdateCardButton(title: "update.card.action.install_now".localized) {
                        manager.installNow()
                    }
                    UpdateCardSecondaryButton(title: "update.card.action.later".localized) {
                        manager.installLater()
                    }
                }
            }

        case .installing:
            card(
                icon: "arrow.triangle.2.circlepath",
                title: versioned("update.card.installing", fallback: "update.card.installing.unknown"),
                subtitle: "update.card.installing.hint".localized
            ) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
            }

        case .failed:
            card(
                icon: "exclamationmark.arrow.circlepath",
                title: "update.card.failed".localized,
                subtitle: "update.card.failed.hint".localized
            ) {
                UpdateCardButton(title: "update.card.action.retry".localized) {
                    manager.retryPendingUpdate()
                }
            }
        }
    }

    private func card<Controls: View>(
        icon: String,
        title: String,
        subtitle: String?,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }

            controls()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardChrome(
            radius: Theme.Layout.cardRadius,
            fill: Theme.accent.opacity(0.12),
            stroke: Theme.accent.opacity(0.22)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Layout.cardRadius, style: .continuous))
    }

    private func versioned(_ key: String, fallback: String) -> String {
        manager.pendingVersion.map { key.localized($0) } ?? fallback.localized
    }

    private func versioned(_ key: String, version: String, fallback: String) -> String {
        version.isEmpty ? fallback.localized : key.localized(version)
    }
}

private struct UpdateCardButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
}

private struct UpdateCardSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
