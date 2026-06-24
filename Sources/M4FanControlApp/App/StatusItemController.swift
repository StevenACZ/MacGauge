import AppKit
import Combine
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

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 520)
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

        model.settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem(snapshot: model.monitor.snapshot)
                }
            }
            .store(in: &cancellables)

        updateStatusItem(snapshot: model.monitor.snapshot)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateStatusItem(snapshot: FanSnapshot) {
        let temperature = AppFormatters.temperature(snapshot.temperatureCelsius, unit: model.settings.temperatureUnit)
        let color = statusColor(for: snapshot.temperatureCelsius)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        ]
        let title = NSAttributedString(string: temperature, attributes: attributes)
        statusItem.button?.attributedTitle = title
        statusItem.button?.image = FanIconRenderer.image(color: color, rotation: rotation)
        statusItem.length = min(max(48, ceil(title.size().width) + 28), 66)
        updateAnimation(snapshot: snapshot)
    }

    private func updateAnimation(snapshot: FanSnapshot) {
        let interval = model.settings.animateFanIcon
            ? model.settings.visualRules.animationInterval(for: snapshot.temperatureCelsius)
            : nil
        guard interval != currentAnimationInterval else { return }
        currentAnimationInterval = interval
        animationTimer?.invalidate()
        animationTimer = nil

        guard let interval else {
            rotation = 0
            statusItem.button?.image = FanIconRenderer.image(color: statusColor(for: snapshot.temperatureCelsius), rotation: rotation)
            return
        }

        animationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.rotation = (self.rotation + 45).truncatingRemainder(dividingBy: 360)
                self.statusItem.button?.image = FanIconRenderer.image(
                    color: self.statusColor(for: self.model.monitor.snapshot.temperatureCelsius),
                    rotation: self.rotation
                )
            }
        }
    }

    private func statusColor(for temperature: Double?) -> NSColor {
        switch model.settings.visualRules.band(for: temperature) {
        case .normal:
            return NSColor(hexString: model.settings.normalColorHex) ?? .labelColor
        case .medium:
            return NSColor(hexString: model.settings.mediumColorHex) ?? .systemOrange
        case .hot:
            return NSColor(hexString: model.settings.hotColorHex) ?? .systemRed
        }
    }
}
