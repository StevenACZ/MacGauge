import AppKit
import Combine
import SwiftUI

/// The label's laid-out width, reported back so the controller can size the
/// status item — the style settings (spacing, graph length) change it live.
private struct StatusLabelWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// One system-module menu bar item (CPU, RAM, or network): a SwiftUI label
/// embedded in the status button plus a detail popover. Each module stays an
/// independent item with its own click target and drag position.
@MainActor
final class MetricStatusItemController: NSObject {
    struct Configuration {
        let autosaveName: String
        let accessibilityTitle: String
        let makeLabel: () -> AnyView
        let makeDetail: () -> AnyView
        var onPopoverOpen: (() -> Void)?
    }

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let configuration: Configuration
    private var labelHostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()

    init(configuration: Configuration) {
        self.configuration = configuration
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = configuration.autosaveName

        super.init()

        popover.behavior = .transient
        popover.animates = true
        // Detail content is built on show and dropped on close: a hosting
        // controller that merely exists keeps its whole SwiftUI graph live,
        // re-rendering and animating on every stats tick while closed.
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityTitle(configuration.accessibilityTitle)

            let hostingView = NSHostingView(rootView: wrappedLabel())
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
        labelHostingView?.rootView = wrappedLabel()
        (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = configuration.makeDetail()
        updateLength()
    }

    private func wrappedLabel() -> AnyView {
        AnyView(
            configuration.makeLabel()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: StatusLabelWidthKey.self, value: proxy.size.width)
                    }
                )
                .onPreferenceChange(StatusLabelWidthKey.self) { [weak self] width in
                    Task { @MainActor in
                        self?.applyLength(labelWidth: width)
                    }
                }
        )
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            button.bounce()
            configuration.onPopoverOpen?()
            let detailController = NSHostingController(rootView: configuration.makeDetail())
            detailController.sizingOptions = [.preferredContentSize]
            popover.contentViewController = detailController
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updateLength() {
        guard let labelHostingView else { return }
        applyLength(labelWidth: labelHostingView.fittingSize.width)
    }

    private func applyLength(labelWidth: CGFloat) {
        guard labelWidth > 0 else { return }
        // No slack: at Together spacing the item hugs its content so the only
        // gap left is the system's own one between status items.
        let width = ceil(labelWidth)
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }
}

extension MetricStatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Drop the SwiftUI graph so a closed popover costs nothing.
        popover.contentViewController = nil
    }
}
