import AppKit
import Combine
import SwiftUI

/// The system modules at Together spacing: every enabled module renders to
/// the left of the fan inside the fan's own status item, so the whole group
/// is one menu bar item that ⌘-drag moves together. Clicks stay per module —
/// each click on a module segment opens that module's detail popover,
/// anchored to the segment, using the frames the label reports back from
/// SwiftUI layout.
@MainActor
final class FusedModulesStrip: NSObject, FanItemLeadingContent {
    private let model: AppModel
    private let networkInfoMonitor: NetworkInfoMonitor
    private weak var host: StatusItemController?
    /// Injected by the coordinator so the detail-view construction lives in
    /// exactly one place, shared with the split per-module items.
    private let makeDetail: (SystemModuleKind) -> AnyView

    private let hostingView: NSHostingView<AnyView>
    private var popovers: [SystemModuleKind: NSPopover] = [:]
    private var segmentFrames: [SystemModuleKind: CGRect] = [:]
    private(set) var modules: [SystemModuleKind]
    private var cancellables = Set<AnyCancellable>()

    var view: NSView { hostingView }

    var accessibilityTitle: String {
        modules.map(\.localizedName).joined(separator: ", ")
    }

    init(
        model: AppModel,
        networkInfoMonitor: NetworkInfoMonitor,
        modules: [SystemModuleKind],
        host: StatusItemController,
        makeDetail: @escaping (SystemModuleKind) -> AnyView
    ) {
        self.model = model
        self.networkInfoMonitor = networkInfoMonitor
        self.modules = modules
        self.host = host
        self.makeDetail = makeDetail
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        super.init()

        hostingView.rootView = makeLabel()
        syncPopovers()

        // Rebuild every view when the app language changes.
        LocalizationManager.shared.$bundle
            .dropFirst()
            .sink { [weak self] _ in
                self?.rebuildViews()
            }
            .store(in: &cancellables)
    }

    func setModules(_ modules: [SystemModuleKind]) {
        guard modules != self.modules else { return }
        self.modules = modules
        syncPopovers()
        rebuildViews()
    }

    func rebuildViews() {
        hostingView.rootView = makeLabel()
        for (module, popover) in popovers where popover.contentViewController != nil {
            (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = detailRoot(module)
        }
        host?.leadingContentDidResize()
    }

    // MARK: - Views

    private func detailRoot(_ module: SystemModuleKind) -> AnyView {
        AnyView(makeDetail(module).background(Color(nsColor: .windowBackgroundColor)))
    }

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
                    self.host?.leadingContentDidResize()
                }
            }
        )
    }

    // MARK: - Popovers

    private func syncPopovers() {
        for module in SystemModuleKind.allCases {
            if modules.contains(module) {
                if popovers[module] == nil {
                    popovers[module] = makePopover()
                }
            } else if let popover = popovers[module] {
                popover.performClose(nil)
                popovers[module] = nil
            }
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // Detail content is built on show and dropped on close: a hosting
        // controller that merely exists keeps its whole SwiftUI graph live,
        // re-rendering and animating on every stats tick while closed.
        popover.delegate = self
        return popover
    }

    func closePopovers() {
        for popover in popovers.values where popover.isShown {
            popover.performClose(nil)
        }
    }

    func handleClick(in button: NSStatusBarButton) -> Bool {
        guard let x = clickX(in: button) else { return false }
        // The fan starts half a gap past the strip; anything beyond is its.
        guard x <= hostingView.bounds.maxX + ModuleSpacingLevel.fusedModuleGap / 2 else { return false }

        let clicked = clickedModule(atX: x)
        if let shown = popovers.first(where: { $0.value.isShown }) {
            shown.value.performClose(nil)
            guard shown.key != clicked else { return true }
        }
        guard let clicked, let popover = popovers[clicked] else { return true }

        UpdateManager.shared.popoverDidOpen()
        if clicked == .network {
            networkInfoMonitor.refresh()
        }
        let controller = NSHostingController(rootView: detailRoot(clicked))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        popover.show(relativeTo: anchorRect(for: clicked, in: button), of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        return true
    }

    /// From the pointer, not the event: since macOS 27 the menu bar agent
    /// forwards every status item click located at the button's center.
    private func clickX(in button: NSStatusBarButton) -> CGFloat? {
        guard let window = button.window else { return nil }
        let mouse = NSEvent.mouseLocation
        let pointInWindow: NSPoint
        if NSMouseInRect(mouse, window.frame, false) {
            pointInWindow = window.convertPoint(fromScreen: mouse)
        } else if let event = NSApp.currentEvent {
            pointInWindow = event.locationInWindow
        } else {
            return nil
        }
        return hostingView.convert(pointInWindow, from: nil).x
    }

    /// Segment whose horizontal range is nearest to the click; clicks in the
    /// gaps resolve to the closest neighbor.
    private func clickedModule(atX x: CGFloat) -> SystemModuleKind? {
        guard !segmentFrames.isEmpty else { return modules.first }
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
        guard let frame = segmentFrames[module] else { return button.bounds }
        let rectInButton = hostingView.convert(frame, to: button)
        return NSRect(
            x: rectInButton.minX,
            y: button.bounds.minY,
            width: rectInButton.width,
            height: button.bounds.height
        )
    }
}

extension FusedModulesStrip: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        // Drop the SwiftUI graph so a closed popover costs nothing.
        guard let closed = notification.object as? NSPopover else { return }
        closed.contentViewController = nil
    }
}
