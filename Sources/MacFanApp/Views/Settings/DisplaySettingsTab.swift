import MacFanCore
import SwiftUI

struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var monitor: FanMonitor

    /// False while another tab is selected so the live preview stops ticking.
    let isActive: Bool

    private let animationRules = FanAnimationRules()

    var body: some View {
        SettingsPane {
            menuBarItemSurface
            temperatureBandsSurface
            modulesSurface
        }
    }

    // MARK: - Menu bar item

    private var menuBarItemSurface: some View {
        SettingsSurface(icon: "fanblades", title: "settings.display.menubar_item".localized) {
            HStack {
                Spacer(minLength: 0)
                MenuBarItemPreview(
                    temperatureText: AppFormatters.temperature(
                        monitor.snapshot.temperatureCelsius,
                        unit: settings.temperatureUnit
                    ),
                    color: currentBandColor,
                    degreesPerSecond: previewDegreesPerSecond,
                    isPaused: !isActive
                )
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.caption".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)

            SettingsDivider()

            SettingsRow(
                title: "settings.display.animate_icon".localized,
                subtitle: "settings.display.animate_icon.caption".localized
            ) {
                Toggle("", isOn: $settings.animateFanIcon)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
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

    private var previewDegreesPerSecond: Double {
        guard settings.animateFanIcon else { return 0 }
        let fan = monitor.snapshot.fan
        return animationRules.rotationDegreesPerSecond(
            currentRPM: fan?.currentRPM,
            targetRPM: fan?.targetRPM,
            minRPM: fan?.minRPM,
            maxRPM: fan?.maxRPM
        ) ?? 0
    }

    // MARK: - Temperature bands

    private var temperatureBandsSurface: some View {
        SettingsSurface(icon: "thermometer.medium", title: "settings.display.bands.title".localized) {
            Text("settings.display.bands.caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TemperatureBandsEditor(
                normalUpper: normalUpperBinding,
                hotLower: hotLowerBinding,
                normalColor: Color(hexString: settings.normalColorHex),
                mediumColor: Color(hexString: settings.mediumColorHex),
                hotColor: Color(hexString: settings.hotColorHex)
            )
            .padding(.vertical, 4)

            SettingsDivider()

            visualThresholdRow(
                title: "settings.display.normal".localized,
                thresholdLabel: "settings.display.up_to".localized,
                value: normalUpperBinding,
                colorHex: colorHexBinding(\.normalColorHex)
            )

            SettingsDivider()

            visualBandRow(
                title: "settings.display.medium".localized,
                rangeText: "\(Int(settings.normalUpperCelsius.rounded()))-\(Int(settings.hotLowerCelsius.rounded())) °C",
                colorHex: colorHexBinding(\.mediumColorHex)
            )

            SettingsDivider()

            visualThresholdRow(
                title: "settings.display.hot".localized,
                thresholdLabel: "settings.display.from".localized,
                value: hotLowerBinding,
                colorHex: colorHexBinding(\.hotColorHex)
            )
        }
    }

    /// Thresholds stay ordered with a visible middle band: the normal ceiling
    /// can never climb into the hot floor and vice versa.
    private var normalUpperBinding: Binding<Double> {
        Binding {
            settings.normalUpperCelsius
        } set: { value in
            guard value.isFinite else { return }
            settings.normalUpperCelsius = min(max(value.rounded(), 20), settings.hotLowerCelsius - 5)
        }
    }

    private var hotLowerBinding: Binding<Double> {
        Binding {
            settings.hotLowerCelsius
        } set: { value in
            guard value.isFinite else { return }
            settings.hotLowerCelsius = max(min(value.rounded(), 95), settings.normalUpperCelsius + 5)
        }
    }

    private func colorHexBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<String> {
        Binding {
            settings[keyPath: keyPath]
        } set: { hex in
            settings[keyPath: keyPath] = hex
        }
    }

    private func visualThresholdRow(
        title: String,
        thresholdLabel: String,
        value: Binding<Double>,
        colorHex: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(thresholdLabel)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Text("°C")
                .foregroundStyle(.secondary)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    private func visualBandRow(title: String, rangeText: String, colorHex: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 82, alignment: .leading)

            Text(rangeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.Anim.smooth, value: rangeText)

            Spacer()

            ColorPresetPicker(selection: colorHex)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Menu bar modules

    private var modulesSurface: some View {
        SettingsSurface(icon: "menubar.rectangle", title: "settings.display.menubar_modules".localized) {
            SettingsRow(
                title: "settings.display.module_cpu".localized,
                subtitle: "settings.display.module_cpu.caption".localized,
                icon: "cpu"
            ) {
                Toggle("", isOn: $settings.showsCPUModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: "settings.display.module_memory".localized,
                subtitle: "settings.display.module_memory.caption".localized,
                icon: "memorychip"
            ) {
                Toggle("", isOn: $settings.showsMemoryModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsRow(
                title: "settings.display.module_network".localized,
                subtitle: "settings.display.module_network.caption".localized,
                icon: "network"
            ) {
                Toggle("", isOn: $settings.showsNetworkModule)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }
}

/// Faithful mock of the status item: the same renderer, icon size, and colors
/// the menu bar uses, spinning at the fan's real animation speed.
private struct MenuBarItemPreview: View {
    let temperatureText: String
    let color: Color
    let degreesPerSecond: Double
    let isPaused: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: degreesPerSecond <= 0 || isPaused)) { timeline in
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        )
        .animation(Theme.Anim.smooth, value: temperatureText)
        .accessibilityLabel("settings.display.menubar_item".localized)
    }
}

/// Interactive 30-90 °C strip: three colored bands with two draggable handles
/// on the thresholds. Text fields next to it keep precise entry available.
private struct TemperatureBandsEditor: View {
    @Binding var normalUpper: Double
    @Binding var hotLower: Double

    let normalColor: Color
    let mediumColor: Color
    let hotColor: Color

    @State private var activeHandle: Handle?

    private enum Handle {
        case normal
        case hot
    }

    private let scale: ClosedRange<Double> = 30...90
    private let barHeight: CGFloat = 26
    private let handleSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        segment(normalColor)
                            .frame(width: position(of: normalUpper, in: width))
                        segment(mediumColor)
                            .frame(width: max(0, position(of: hotLower, in: width) - position(of: normalUpper, in: width)))
                        segment(hotColor)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    handle(.normal, value: normalUpper, width: width)
                    handle(.hot, value: hotLower, width: width)
                }
                .coordinateSpace(name: "temperature-bands")
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: normalUpper)
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: hotLower)
            }
            .frame(height: barHeight)

            HStack {
                Text("\(Int(scale.lowerBound))°")
                Spacer()
                Text("\(Int(scale.upperBound))°")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private func segment(_ color: Color) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func handle(_ kind: Handle, value: Double, width: CGFloat) -> some View {
        let isDragging = activeHandle == kind
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 3 : 1.5, y: 1)
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: handleSize, height: handleSize)
            .scaleEffect(isDragging ? 1.18 : 1)
            .animation(Theme.Anim.hover, value: isDragging)
        }
        .position(x: position(of: value, in: width), y: barHeight / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("temperature-bands"))
                .onChanged { drag in
                    activeHandle = kind
                    let temperature = temperature(at: drag.location.x, in: width)
                    switch kind {
                    case .normal:
                        normalUpper = temperature
                    case .hot:
                        hotLower = temperature
                    }
                }
                .onEnded { _ in
                    activeHandle = nil
                }
        )
        .accessibilityLabel(
            kind == .normal
                ? "settings.display.normal".localized
                : "settings.display.hot".localized
        )
        .accessibilityValue("\(Int(value.rounded())) °C")
    }

    private func position(of temperature: Double, in width: CGFloat) -> CGFloat {
        let clamped = min(max(temperature, scale.lowerBound), scale.upperBound)
        let fraction = (clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
        return CGFloat(fraction) * width
    }

    private func temperature(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return scale.lowerBound }
        let fraction = Double(min(max(x / width, 0), 1))
        return (scale.lowerBound + fraction * (scale.upperBound - scale.lowerBound)).rounded()
    }
}
