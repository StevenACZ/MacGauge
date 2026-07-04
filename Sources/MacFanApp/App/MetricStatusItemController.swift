import AppKit
import Combine
import SwiftUI

/// One system-module menu bar item (CPU, RAM, or network): a SwiftUI label
/// embedded in the status button plus a detail popover. Labels reserve their
/// widest-case width themselves, so the item length only needs recomputing
/// when the views are (re)built.
@MainActor
final class MetricStatusItemController: NSObject {
    struct Configuration {
        let autosaveName: String
        let accessibilityTitle: String
        let makeLabel: () -> AnyView
        let makeDetail: () -> AnyView
        var onPopoverOpen: (() -> Void)?
        var onPopoverClose: (() -> Void)?
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let configuration: Configuration
    private var labelHostingView: NSHostingView<AnyView>?
    private var detailHostingController: NSHostingController<AnyView>?
    private var cancellables = Set<AnyCancellable>()

    init(configuration: Configuration) {
        self.configuration = configuration
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = configuration.autosaveName

        super.init()

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let detailController = NSHostingController(rootView: configuration.makeDetail())
        detailController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = detailController
        detailHostingController = detailController

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityTitle(configuration.accessibilityTitle)

            let hostingView = NSHostingView(rootView: configuration.makeLabel())
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            labelHostingView = hostingView
        }

        // Rebuild both views when the app language changes.
        LocalizationManager.shared.$bundle
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildViews()
            }
            .store(in: &cancellables)

        updateLength()
    }

    deinit {
        // NSStatusBar keeps items alive until they are explicitly removed.
        MainActor.assumeIsolated {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }

    func rebuildViews() {
        labelHostingView?.rootView = configuration.makeLabel()
        detailHostingController?.rootView = configuration.makeDetail()
        updateLength()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            bounceStatusButton(button)
            configuration.onPopoverOpen?()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateLength() {
        guard let labelHostingView else { return }
        let width = ceil(labelHostingView.fittingSize.width) + 4
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
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
}

extension MetricStatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        configuration.onPopoverClose?()
    }
}
