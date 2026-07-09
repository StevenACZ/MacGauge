import MacFanCore
import SwiftUI

/// The fan status-item card: a live mock of the menu bar item plus the
/// animate toggle and the color-style picker.
struct FanMenuBarItemSection: View {
    @ObservedObject var settings: AppSettingsStore
    let monitor: FanMonitor
    let isActive: Bool

    var body: some View {
        SettingsSurface(icon: "fanblades", title: "settings.display.menubar_item".localized) {
            HStack {
                Spacer(minLength: 0)
                FanMenuBarItemLivePreview(settings: settings, monitor: monitor, isActive: isActive)
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.caption".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            SettingsDivider()

            SettingsToggleRow(
                title: "settings.display.animate_icon".localized,
                subtitle: "settings.display.animate_icon.caption".localized,
                trailingWidth: 60,
                isOn: $settings.animateFanIcon,
                isDisabled: settings.performanceMode == .efficient
            )

            if settings.performanceMode == .efficient {
                Label(
                    "settings.display.animate_icon.efficient_notice".localized,
                    systemImage: "leaf.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            SettingsDivider()

            StylePickerRow(
                title: "settings.display.modules.color".localized,
                caption: "fan.color.caption".localized,
                options: FanColorStyle.allCases,
                label: \.localizedName,
                selection: $settings.fanColorStyle
            )
        }
    }
}

/// The only view in the tab that observes the monitor, so its 1 Hz snapshot
/// updates re-render just this preview instead of the whole Display tab.
private struct FanMenuBarItemLivePreview: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor
    let isActive: Bool

    private let animationRules = FanAnimationRules()

    var body: some View {
        MenuBarItemPreview(
            temperatureText: AppFormatters.temperature(
                monitor.snapshot.temperatureCelsius,
                unit: settings.temperatureUnit
            ),
            color: fanPreviewColor,
            degreesPerSecond: previewDegreesPerSecond,
            isPaused: !isActive
        )
    }

    private var currentBandColor: Color {
        switch settings.visualRules.band(for: monitor.snapshot.temperatureCelsius) {
        case .normal:
            return Color(hexString: settings.normalColorHex)
        case .medium:
            return Color(hexString: settings.mediumColorHex)
        case .hot:
            return Color(hexString: settings.hotColorHex)
        }
    }

    /// Mirrors StatusItemController.statusColor for the always-dark preview.
    private var fanPreviewColor: Color {
        switch settings.fanColorStyle {
        case .temperature:
            return currentBandColor
        case .mono:
            return .white
        case .gray:
            return Color(nsColor: .systemGray)
        }
    }

    private var previewDegreesPerSecond: Double {
        // Mirrors the real status item: Efficient keeps the icon still.
        guard settings.animateFanIcon, settings.performanceMode == .full else { return 0 }
        let fan = monitor.snapshot.fan
        return animationRules.rotationDegreesPerSecond(
            currentRPM: fan?.currentRPM,
            targetRPM: fan?.targetRPM,
            minRPM: fan?.minRPM,
            maxRPM: fan?.maxRPM
        ) ?? 0
    }
}

/// Faithful mock of the status item: the same renderer, icon size, and colors
/// the menu bar uses, spinning at the fan's real animation speed.
private struct MenuBarItemPreview: View {
    let temperatureText: String
    let color: Color
    let degreesPerSecond: Double
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(minimumInterval: 1.0 / 30.0, paused: degreesPerSecond <= 0 || isPaused || reduceMotion)
        ) { timeline in
            let rotation =
                degreesPerSecond > 0
                ? (timeline.date.timeIntervalSinceReferenceDate * degreesPerSecond).truncatingRemainder(dividingBy: 360)
                : 0
            HStack(spacing: 4) {
                if let icon = FanIconRenderer.image(color: NSColor(color), rotation: rotation) {
                    Image(nsImage: icon)
                }
                Text(temperatureText)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .menuBarMockCapsule(verticalPadding: 5)
        .animation(Theme.Anim.smooth, value: temperatureText)
        .accessibilityLabel("settings.display.menubar_item".localized)
    }
}
