import AppKit

/// The fan icon and temperature drawn as the last segment of the Together
/// block, where the status item button also hosts the modules. Frames only
/// swap a cached bitmap, like the standalone button image. Clicks fall
/// through to the status bar button.
final class FanSegmentView: NSView {
    static let iconSize = NSSize(width: 18, height: 18)

    var image: NSImage? {
        didSet {
            guard image !== oldValue else { return }
            needsDisplay = true
        }
    }

    var title = NSAttributedString() {
        didSet {
            guard !title.isEqual(to: oldValue) else { return }
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.iconSize.width + ceil(title.size().width), height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        let iconRect = NSRect(
            x: 0,
            y: ((bounds.height - Self.iconSize.height) / 2).rounded(),
            width: Self.iconSize.width,
            height: Self.iconSize.height
        )
        image?.draw(in: iconRect)
        let titleSize = title.size()
        title.draw(at: NSPoint(x: iconRect.maxX, y: (bounds.height - titleSize.height) / 2))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
