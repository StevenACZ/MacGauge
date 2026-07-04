import AppKit
import Combine
import SwiftUI

/// The fused system-modules menu bar item used at Together spacing: every
/// enabled module renders inside one status item so even the system's own
/// gap between separate items disappears. Clicks stay per-module — the
/// whole-item highlight is suppressed and each click routes to the clicked
/// segment's detail popover, anchored to that segment, using the frames the
/// label reports back from SwiftUI layout.
@MainActor
final class FusedModulesStatusItemController: NSObject {
    private let model: AppModel
    private let processMonitor: ProcessStatsMonitor
    private let networkInfoMonitor: NetworkInfoMonitor

    private let statusItem: NSStatusItem
    private var labelHostingView: NSHostingView<AnyView>?
    private var popovers: [SystemModuleKind: NSPopover] = [:]
    private var segmentFrames: [SystemModuleKind: CGRect] = [:]
    private(set) var modules: [SystemModuleKind]
    private var cancellables = Set<AnyCancellable>()

    init(
        model: AppModel,
        processMonitor: ProcessStatsMonitor,
        networkInfoMonitor: NetworkInfoMonitor,
        modules: [SystemModuleKind]
    ) {
        self.model = model
        self.processMonitor = processMonitor
        self.networkInfoMonitor = networkInfoMonitor
        self.modules = modules
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "MacFan.modules"

        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            // No whole-item flash: the modules must keep reading as
            // independent controls even while sharing the item.
            (button.cell as? NSButtonCell)?.highlightsBy = []

            let hostingView = NSHostingView(rootView: makeLabel())
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            ])
            labelHostingView = hostingView
        }

        syncPopovers()
        updateAccessibility()

        // Rebuild every view when the app language changes.
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

    func setModules(_ modules: [SystemModuleKind]) {
        guard modules != self.modules else { return }
        self.modules = modules
        syncPopovers()
        rebuildViews()
    }

    func rebuildViews() {
        labelHostingView?.rootView = makeLabel()
        for (module, popover) in popovers where popover.contentViewController != nil {
            (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = makeDetail(for: module)
        }
        updateAccessibility()
        updateLength()
    }

    // MARK: - Views

    private func makeLabel() -> AnyView {
        AnyView(
            FusedModulesStatusLabel(
                stats: model.systemStats,
                settings: model.settings,
                modules: modules
            )
            .onPreferenceChange(ModuleSegmentFramesKey.self) { [weak self] frames in
                Task { @MainActor in
                    guard let self else { return }
                    self.segmentFrames = frames
                    self.updateLength()
                }
            }
        )
    }

    private func makeDetail(for module: SystemModuleKind) -> AnyView {
        let animated = model.settings.performanceMode == .full
        switch module {
        case .cpu:
            return AnyView(
                CPUModuleDetailView(
                    stats: model.systemStats,
                    processes: processMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        case .memory:
            return AnyView(
                MemoryModuleDetailView(
                    stats: model.systemStats,
                    processes: processMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        case .network:
            return AnyView(
                NetworkModuleDetailView(
                    stats: model.systemStats,
                    info: networkInfoMonitor,
                    settings: model.settings,
                    tickSeconds: model.settings.controlTickSeconds,
                    animated: animated
                )
            )
        }
    }

    // MARK: - Popovers

    private func syncPopovers() {
        for module in SystemModuleKind.allCases {
            if modules.contains(module) {
                if popovers[module] == nil {
                    popovers[module] = makePopover(for: module)
                }
            } else if let popover = popovers[module] {
                popover.performClose(nil)
                popovers[module] = nil
            }
        }
    }

    private func makePopover(for module: SystemModuleKind) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // Detail content is built on show and dropped on close: a hosting
        // controller that merely exists keeps its whole SwiftUI graph live,
        // re-rendering and animating on every stats tick while closed.
        popover.delegate = self
        return popover
    }

    @objc private func handleClick() {
        guard let button = statusItem.button else { return }

        let clicked = clickedModule(in: button)
        if let shown = popovers.first(where: { $0.value.isShown }) {
            shown.value.performClose(nil)
            guard shown.key != clicked else { return }
        }
        guard let clicked, let popover = popovers[clicked] else { return }

        if clicked == .network {
            networkInfoMonitor.refresh()
        }
        let controller = NSHostingController(rootView: makeDetail(for: clicked))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: anchorRect(for: clicked, in: button), of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Segment whose horizontal range is nearest to the click; clicks in the
    /// hairline gaps resolve to the closest neighbor.
    private func clickedModule(in button: NSStatusBarButton) -> SystemModuleKind? {
        guard let hostingView = labelHostingView,
            let event = NSApp.currentEvent,
            !segmentFrames.isEmpty
        else {
            return modules.first
        }

        let locationInButton = button.convert(event.locationInWindow, from: nil)
        let x = hostingView.convert(locationInButton, from: button).x

        let nearest = segmentFrames.min { lhs, rhs in
            distance(from: x, to: lhs.value) < distance(from: x, to: rhs.value)
        }
        return nearest?.key ?? modules.first
    }

    private func distance(from x: CGFloat, to frame: CGRect) -> CGFloat {
        if x < frame.minX { return frame.minX - x }
        if x > frame.maxX { return x - frame.maxX }
        return 0
    }

    private func anchorRect(for module: SystemModuleKind, in button: NSStatusBarButton) -> NSRect {
        guard let hostingView = labelHostingView, let frame = segmentFrames[module] else {
            return button.bounds
        }
        let rectInButton = hostingView.convert(frame, to: button)
        return NSRect(
            x: rectInButton.minX,
            y: button.bounds.minY,
            width: rectInButton.width,
            height: button.bounds.height
        )
    }

    private func updateAccessibility() {
        statusItem.button?.setAccessibilityTitle(
            modules.map(\.localizedName).joined(separator: ", ")
        )
    }

    private func updateLength() {
        guard let labelHostingView else { return }
        let width = ceil(labelHostingView.fittingSize.width)
        guard width > 0 else { return }
        if abs(statusItem.length - width) > 0.5 {
            statusItem.length = width
        }
    }
}

extension FusedModulesStatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Drop the SwiftUI graph so a closed popover costs nothing.
        guard let closed = notification.object as? NSPopover else { return }
        closed.contentViewController = nil
    }
}
