import MacFanCore
import SwiftUI

/// Full-width hover-filled row with a leading icon and trailing chevron,
/// used for the popover footer actions.
struct ActionRow: View {
    let icon: String
    let title: String
    var isDestructive = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
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

/// Compact per-fan readout used when the Mac has more than one fan.
struct FanRPMChip: View {
    let fan: FanInfo

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "fan.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(fan.name ?? "popover.fan_fallback".localized(fan.index + 1))
                .foregroundStyle(.secondary)
            Text(AppFormatters.rpm(fan.currentRPM))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.badgeRadius, style: .continuous)
                .fill(Theme.Layout.cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Layout.badgeRadius, style: .continuous)
                        .strokeBorder(Theme.Layout.cardStroke, lineWidth: 1)
                )
        )
        .animation(.default, value: fan.currentRPM)
    }
}
