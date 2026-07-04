import AppKit
import Combine
import MacFanCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: AppModel
    private var hostingController: NSHostingController<MenuBarPopoverView>?
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var rotation: CGFloat = 0
    /// Current animated speed in degrees per second; eases toward
    /// `targetRotationSpeed` every frame so speed changes look fluid.
    private var rotationSpeed: Double = 0
    private var targetRotationSpeed: Double = 0
    private var lastFrameTime: CFTimeInterval?
    private let animationRules = FanAnimationRules()

    private static let animationFrameInterval: TimeInterval = 1.0 / 30.0

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(rootView: MenuBarPopoverView(model: model))
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        self.hostingController = hostingController

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
            model.settings.$animateFanIcon.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.updateStatusItem(snapshot: model.monitor.snapshot)
        }
        .store(in: &cancellables)

        // Rebuild the popover root when the app language changes so every
        // string in the menu-bar panel re-resolves immediately.
        LocalizationManager.shared.$bundle
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.hostingController?.rootView = MenuBarPopoverView(model: self.model)
            }
            .store(in: &cancellables)

        updateStatusItem(snapshot: model.monitor.snapshot)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            bounceStatusButton(button)
            model.refreshHelperState()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func bounceStatusButton(_ button: NSStatusBarButton) {
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        let bounds = layer.bounds
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 0.86, 1.08, 1.0]
        bounce.keyTimes = [0, 0.35, 0.7, 1]
        bounce.duration = 0.28
        bounce.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(bounce, forKey: "bounce")
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
            button.attributedTitle = title
            button.contentTintColor = nil
            button.image = FanIconRenderer.image(color: color, rotation: rotation)
            statusItem.length = min(ceil(button.fittingSize.width), 84)
        }
        updateAnimation(snapshot: snapshot)
    }

    private func updateAnimation(snapshot: FanSnapshot) {
        let fan = snapshot.fan
        targetRotationSpeed =
            model.settings.animateFanIcon
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
        let timer = Timer(timeInterval: Self.animationFrameInterval, repeats: true) { [weak self] _ in
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
