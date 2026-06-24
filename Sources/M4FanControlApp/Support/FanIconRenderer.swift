import AppKit

enum FanIconRenderer {
    static func image(color: NSColor, rotation: CGFloat) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "M4 Fan Control") else {
            return nil
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        color.set()
        let rect = NSRect(x: 1, y: 1, width: 16, height: 16)
        symbol.draw(in: rect, from: .zero, operation: .sourceIn, fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
