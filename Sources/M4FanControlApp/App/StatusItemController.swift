import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()

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
            button.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "M4 Fan Control")
            button.imagePosition = .imageLeading
        }

        model.monitor.$snapshot
            .sink { [weak self] snapshot in
                self?.updateTitle(snapshot: snapshot)
            }
            .store(in: &cancellables)

        model.settings.$temperatureUnit
            .sink { [weak self] _ in
                self?.updateTitle(snapshot: model.monitor.snapshot)
            }
            .store(in: &cancellables)

        updateTitle(snapshot: model.monitor.snapshot)
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

    private func updateTitle(snapshot: FanSnapshot) {
        let temperature = AppFormatters.temperature(snapshot.temperatureCelsius, unit: model.settings.temperatureUnit)
        let rpm = snapshot.fan?.currentRPM.map { "\(Int($0.rounded()))" } ?? "--"
        statusItem.button?.title = " \(temperature) \(rpm)"
    }
}
