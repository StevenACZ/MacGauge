import AppKit
import Combine
import M4FanCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var rotation: CGFloat = 0
    private var currentAnimationInterval: TimeInterval?
    private let animationRules = FanAnimationRules()

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = Self.popoverSize(for: model.settings.controlMode)
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(model: model))

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

        model.settings.$controlMode
            .dropFirst()
            .sink { [weak self] mode in
                self?.updatePopoverSize(for: mode, animated: self?.popover.isShown == true)
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

        updateStatusItem(snapshot: model.monitor.snapshot)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverSize(for: model.settings.controlMode, animated: false)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverSize(for mode: FanControlMode, animated: Bool) {
        let newSize = Self.popoverSize(for: mode)
        guard animated else {
            popover.contentSize = newSize
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = PopoverLayout.modeTransitionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            popover.contentSize = newSize
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
        }
    }

    private static func popoverSize(for mode: FanControlMode) -> NSSize {
        NSSize(width: PopoverLayout.width, height: PopoverLayout.height(for: mode))
    }

    private func updateStatusItem(snapshot: FanSnapshot) {
        let temperature = AppFormatters.temperature(snapshot.temperatureCelsius, unit: model.settings.temperatureUnit)
        let color = statusColor(for: snapshot.temperatureCelsius)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            .baselineOffset: -0.5
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
        let interval = model.settings.animateFanIcon
            ? animationRules.animationInterval(
                currentRPM: fan?.currentRPM,
                targetRPM: fan?.targetRPM,
                minRPM: fan?.minRPM,
                maxRPM: fan?.maxRPM
            )
            : nil
        guard interval != currentAnimationInterval else { return }
        currentAnimationInterval = interval
        animationTimer?.invalidate()
        animationTimer = nil

        guard let interval else {
            rotation = 0
            let color = statusColor(for: snapshot.temperatureCelsius)
            statusItem.button?.contentTintColor = nil
            statusItem.button?.image = FanIconRenderer.image(color: color, rotation: rotation)
            return
        }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rotation = (self.rotation + 45).truncatingRemainder(dividingBy: 360)
                let color = self.statusColor(for: self.model.monitor.snapshot.temperatureCelsius)
                self.statusItem.button?.contentTintColor = nil
                self.statusItem.button?.image = FanIconRenderer.image(
                    color: color,
                    rotation: self.rotation
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
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
