import AppKit

enum FanIconRenderer {
    static func image(color: NSColor, rotation: CGFloat) -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let transform = NSAffineTransform()
        transform.translateX(by: size.width / 2, yBy: size.height / 2)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -size.width / 2, yBy: -size.height / 2)
        transform.concat()

        let rect = NSRect(x: 1, y: 1, width: 16, height: 16)
        if let symbol = configuredSymbol() {
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawFallbackFan(in: rect)
        }

        _ = color
        image.isTemplate = true
        return image
    }

    private static func configuredSymbol() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return ["fanblades.fill", "fanblades", "fan.fill", "fan"]
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "M4 Fan Control") }
            .compactMap { $0.withSymbolConfiguration(configuration) }
            .first
    }

    private static func drawFallbackFan(in rect: NSRect) {
        NSColor.black.setFill()
        let center = NSPoint(x: rect.midX, y: rect.midY)

        for index in 0..<4 {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: CGFloat(index) * 90)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()

            let blade = NSBezierPath(
                roundedRect: NSRect(x: center.x - 2, y: center.y + 1, width: 4, height: 7),
                xRadius: 2,
                yRadius: 2
            )
            blade.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
    }
}
