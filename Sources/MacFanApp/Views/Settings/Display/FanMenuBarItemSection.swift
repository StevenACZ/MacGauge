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
                    .menuBarMockCapsule(verticalPadding: 5)
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            SettingsDivider()

            SettingsGroupHeader(
                title: "settings.display.modules.color".localized,
                caption: "fan.color.caption".localized
            )

            OptionTilePicker(
                options: FanColorStyle.allCases,
                selection: $settings.fanColorStyle,
                label: \.localizedName
            ) { style in
                FanStyleSample(style: style, settings: settings)
            }

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
        }
    }
}

private struct FanStyleSample: View {
    let style: FanColorStyle
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        switch style {
        case .temperature:
            let hexes = [settings.normalColorHex, settings.mediumColorHex, settings.hotColorHex]
            HStack(spacing: 7) {
                ForEach(Array(hexes.enumerated()), id: \.offset) { _, hex in
                    Image(systemName: "fanblades.fill")
                        .foregroundStyle(ModuleColorResolver.menuBarTint(hexString: hex))
                }
            }
            .font(.system(size: 13, weight: .medium))
        case .mono:
            glyph(Color.white)
        case .gray:
            glyph(Color.white.opacity(0.55))
        }
    }

    private func glyph(_ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "fanblades.fill")
            Text(AppFormatters.temperature(56, unit: settings.temperatureUnit))
                .monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
    }
}

/// The only view in the tab that observes the monitor, so its 1 Hz snapshot
/// updates re-render just this preview instead of the whole Display tab.
struct FanMenuBarItemLivePreview: View {
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

    /// Static, already lifted for a dark bar: the renderer bakes the color
    /// into a bitmap, so a dynamic color would resolve against the window.
    private var currentBandColor: Color {
        let hex: String
        switch settings.visualRules.band(for: monitor.snapshot.temperatureCelsius) {
        case .normal:
            hex = settings.normalColorHex
        case .medium:
            hex = settings.mediumColorHex
        case .hot:
            hex = settings.hotColorHex
        }
        return Color(nsColor: AppearancePalette.menuBarVariant(of: NSColor(hexString: hex) ?? .white, isDark: true))
    }

    /// Mirrors StatusItemController.statusColor for the always-dark preview.
    private var fanPreviewColor: Color {
        switch settings.fanColorStyle {
        case .temperature:
            return currentBandColor
        case .mono:
            return .white
        case .gray:
            return Color(nsColor: NSColor.white.withAlphaComponent(0.55))
        }
    }

    private var previewDegreesPerSecond: Double {
        // Mirrors the real status item: Efficient keeps the icon still.
        guard settings.animateFanIcon, settings.performanceMode == .full else { return 0 }
        return animationRules.rotationDegreesPerSecond(
            fan: monitor.snapshot.fan,
            cpuPercent: nil,
            temperatureCelsius: monitor.snapshot.temperatureCelsius
        )
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
        .animation(Theme.Anim.smooth, value: temperatureText)
        .accessibilityLabel("settings.display.menubar_item".localized)
    }
}
