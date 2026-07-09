import SwiftUI

enum SettingsLayout {
    static let trailingControlWidth: CGFloat = 220
    /// Window width (680) minus the window's leading (20) and trailing (12)
    /// paddings. Every tab is pinned to this width so one tab's rigid rows
    /// can never widen the shared tab stack and eat the window margins.
    static let contentWidth: CGFloat = 648
}

struct SettingsTrailingControl<Content: View>: View {
    var width: CGFloat = SettingsLayout.trailingControlWidth
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
        }
        .frame(width: width, alignment: .trailing)
    }
}

struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.vertical, 2)
        }
    }
}

struct SettingsSurface<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, alignment: .leading)

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    /// Narrow panes (next to the Display sidebar) pass a smaller width for
    /// compact controls like toggles, so the text column keeps the room
    /// instead of a mostly-empty reserved column.
    var trailingWidth: CGFloat = SettingsLayout.trailingControlWidth
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 24)
            SettingsTrailingControl(width: trailingWidth) {
                content()
            }
        }
        .padding(.vertical, 2)
    }
}

/// The recurring settings row whose trailing control is a bare switch.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var trailingWidth: CGFloat = SettingsLayout.trailingControlWidth
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, icon: icon, trailingWidth: trailingWidth) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isDisabled)
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.primary.opacity(0.04))
    }
}
