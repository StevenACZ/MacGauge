import AppKit
import Combine
import MacFanCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var rotation: CGFloat = 0
    /// Current animated speed in degrees per second; eases toward
    /// `targetRotationSpeed` every frame so speed changes look fluid.
    private var rotationSpeed: Double = 0
    private var targetRotationSpeed: Double = 0
    private var lastFrameTime: CFTimeInterval?
    private let animationRules = FanAnimationRules()

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = true
        // Content is built on show and dropped on close: a hosting controller
        // that merely exists keeps its whole SwiftUI graph live (sizing keeps
        // the view loaded), re-rendering and animating on every monitor tick
        // even while the popover is closed.
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
        }

        model.monitor.$snapshot
            .sink { [weak self] snapshot in
                self?.updateStatusItem(snapshot: snapshot)
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            model.settings.$temperatureUnit.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$normalColorHex.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$mediumColorHex.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$hotColorHex.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$fanColorStyle.map { _ in () }.eraseToAnyPublisher(),
            model.settings.$animateFanIcon.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.updateStatusItem(snapshot: model.monitor.snapshot)
        }
        .store(in: &cancellables)

        // $performanceMode publishes before the property is set, so the
        // received value is what decides whether the fan spins up or coasts
        // down right away.
        model.settings.$performanceMode
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] mode in
                guard let self else { return }
                self.updateAnimation(snapshot: self.model.monitor.snapshot, mode: mode)
            }
            .store(in: &cancellables)

        // Rebuild the popover root when the app language changes so every
        // string in the menu-bar panel re-resolves immediately (closed
        // popovers have no content and resolve strings on next open).
        LocalizationManager.shared.$bundle
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                (self.popover.contentViewController as? NSHostingController<MenuBarPopoverView>)?
                    .rootView = MenuBarPopoverView(model: self.model)
            }
            .store(in: &cancellables)

        updateStatusItem(snapshot: model.monitor.snapshot)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            button.bounce()
            model.refreshHelperState()
            let controller = NSHostingController(rootView: MenuBarPopoverView(model: model))
            controller.sizingOptions = [.preferredContentSize]
            popover.contentViewController = controller
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem(snapshot: FanSnapshot) {
        let temperature = AppFormatters.temperature(snapshot.temperatureCelsius, unit: model.settings.temperatureUnit)
        let color = statusColor(for: snapshot.temperatureCelsius)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .baselineOffset: -0.5,
        ]
        let title = NSAttributedString(string: " \(temperature)", attributes: attributes)
        if let button = statusItem.button {
            // The monitor ticks every second; skip the title reassignment and
            // the fitting-size pass when nothing visible changed.
            if !button.attributedTitle.isEqual(title) {
                button.attributedTitle = title
                statusItem.length = min(ceil(button.fittingSize.width), 84)
            }
            let image = FanIconRenderer.image(color: color, rotation: rotation)
            if button.image !== image {
                button.contentTintColor = nil
                button.image = image
            }
        }
        updateAnimation(snapshot: snapshot)
    }

    private func updateAnimation(snapshot: FanSnapshot, mode: PerformanceMode? = nil) {
        let fan = snapshot.fan
        // Every frame that lands a new image makes AppKit re-snapshot the
        // status item (several ms each), so the continuous spin is a Full
        // luxury; Efficient keeps the icon still and lets color carry state.
        let spins = model.settings.animateFanIcon && (mode ?? model.settings.performanceMode) == .full
        targetRotationSpeed =
            spins
            ? animationRules.rotationDegreesPerSecond(
                currentRPM: fan?.currentRPM,
                targetRPM: fan?.targetRPM,
                minRPM: fan?.minRPM,
                maxRPM: fan?.maxRPM
            ) ?? 0
            : 0

        if targetRotationSpeed > 0 || rotationSpeed > 0 {
            startAnimationTimerIfNeeded()
        }
    }

    private func startAnimationTimerIfNeeded() {
        guard animationTimer == nil else { return }
        lastFrameTime = nil
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.stepAnimationFrame()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    /// Integrates the rotation each frame while easing the speed toward its
    /// target, so the blades accelerate and coast down instead of jumping
    /// between fixed step rates. The timer stops itself once spun down.
    private func stepAnimationFrame() {
        let now = CACurrentMediaTime()
        let elapsed = min(max(now - (lastFrameTime ?? now), 0), 0.1)
        lastFrameTime = now

        let blend = 1 - exp(-elapsed * 4)
        rotationSpeed += (targetRotationSpeed - rotationSpeed) * blend

        if targetRotationSpeed <= 0, rotationSpeed < 4 {
            rotationSpeed = 0
            rotation = 0
            animationTimer?.invalidate()
            animationTimer = nil
            lastFrameTime = nil
            redrawFanIcon()
            return
        }

        rotation = (rotation + rotationSpeed * elapsed).truncatingRemainder(dividingBy: 360)
        redrawFanIcon()
    }

    private func redrawFanIcon() {
        guard let button = statusItem.button else { return }
        let color = statusColor(for: model.monitor.snapshot.temperatureCelsius)
        let image = FanIconRenderer.image(color: color, rotation: rotation)
        // The renderer caches by rounded degree; skip no-op assignments so
        // slow spins do not redraw the button 30 times a second.
        if button.image !== image {
            button.contentTintColor = nil
            button.image = image
        }
    }

    private func statusColor(for temperature: Double?) -> NSColor {
        switch model.settings.fanColorStyle {
        case .mono:
            return .labelColor
        case .gray:
            return .secondaryLabelColor
        case .temperature:
            break
        }
        switch model.settings.visualRules.band(for: temperature) {
        case .normal:
            return readableMenuBarColor(NSColor(hexString: model.settings.normalColorHex), fallback: .white)
        case .medium:
            return readableMenuBarColor(NSColor(hexString: model.settings.mediumColorHex), fallback: .systemOrange)
        case .hot:
            return readableMenuBarColor(NSColor(hexString: model.settings.hotColorHex), fallback: .systemRed)
        }
    }

    private func readableMenuBarColor(_ color: NSColor?, fallback: NSColor) -> NSColor {
        let source = (color ?? fallback).usingColorSpace(.sRGB) ?? fallback
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let liftedBrightness = max(brightness, 0.82)
        let liftedSaturation = saturation > 0.05 ? max(saturation, 0.58) : saturation
        return NSColor(
            calibratedHue: hue,
            saturation: liftedSaturation,
            brightness: liftedBrightness,
            alpha: alpha > 0 ? alpha : 1
        ).usingColorSpace(.sRGB) ?? fallback
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Drop the SwiftUI graph so a closed popover costs nothing.
        popover.contentViewController = nil
    }
}
