import SwiftUI

enum SettingsLayout {
    /// The window content size and the SwiftUI root frame share this one
    /// constant; the toolbar with the tab bar sits above it.
    static let windowSize = CGSize(width: 800, height: 620)
    /// NSHostingController bridges SwiftUI toolbars from macOS 14; macOS 13
    /// keeps the tab bar and Close button inside the content instead.
    static var bridgesToolbar: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }
    static let leadingPadding: CGFloat = 20
    static let trailingPadding: CGFloat = 12
    static let trailingControlWidth: CGFloat = 220
    /// Every tab is pinned to this width so one tab's rigid rows can never
    /// widen the shared tab stack and eat the window margins.
    static let contentWidth: CGFloat = windowSize.width - leadingPadding - trailingPadding
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
            .padding(.trailing, 8)
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
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.accent.opacity(0.14))
                    )

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
