import AppKit
import SwiftUI

private struct PopoverContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Hosts a module detail popover and owns its size. Left to AppKit, the
/// hosting view jumped to the new height while the window animated on its
/// own, sliding the content under the top edge. Here the hosting view never
/// sizes the window: the popover takes the content's height on every layout,
/// so animated content (the top apps list unrolling) carries the window edge
/// with it frame by frame.
final class PopoverHostingController: NSHostingController<AnyView> {
    private weak var popover: NSPopover?

    /// Hosts `content` in `popover`, sized to the content before it shows.
    static func install(_ content: AnyView, in popover: NSPopover) {
        let controller = PopoverHostingController(content: content, popover: popover)
        popover.contentViewController = controller
        popover.contentSize = controller.sizeThatFits(in: .zero)
    }

    private init(content: AnyView, popover: NSPopover) {
        self.popover = popover
        super.init(rootView: AnyView(EmptyView()))
        sizingOptions = []
        setContent(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setContent(_ content: AnyView) {
        rootView = AnyView(
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: PopoverContentHeightKey.self, value: proxy.size.height)
                    }
                )
                .onPreferenceChange(PopoverContentHeightKey.self) { [weak self] height in
                    MainActor.assumeIsolated {
                        self?.contentHeightDidChange(height)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func contentHeightDidChange(_ height: CGFloat) {
        guard let popover, popover.isShown, height > 0 else { return }
        let target = height.rounded()
        guard abs(popover.contentSize.height - target) >= 1 else { return }
        popover.animates = false
        popover.contentSize = NSSize(width: popover.contentSize.width, height: target)
        popover.animates = true
    }
}
