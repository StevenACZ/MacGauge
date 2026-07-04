import AppKit

@MainActor
enum FanIconRenderer {
    private static var imageCache = [String: NSImage]()
    /// Rotation is cached per rounded degree, so the cache stays small unless
    /// the user cycles through many custom colors; clear it before it can grow
    /// past a few full revolutions worth of entries.
    private static let imageCacheLimit = 1440

    private static let canvasSize = NSSize(width: 18, height: 18)
    private static let symbolRect = NSRect(x: 1, y: 1, width: 16, height: 16)

    private static let symbol: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return ["fanblades.fill", "fanblades", "fan.fill", "fan"]
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "MacGauge") }
            .compactMap { $0.withSymbolConfiguration(configuration) }
            .first
    }()

    /// Optical center of the drawn glyph in canvas coordinates. SF Symbol
    /// canvases carry baseline padding, so the visible blades are not centered
    /// in `symbolRect`; rotating around the canvas center makes them orbit by
    /// about a pixel. Rotation must pivot on this point instead.
    private static let glyphCenter: NSPoint =
        measuredGlyphCenter()
        ?? NSPoint(
            x: canvasSize.width / 2,
            y: canvasSize.height / 2
        )

    static func image(color: NSColor, rotation: CGFloat) -> NSImage? {
        let drawColor = color.usingColorSpace(.sRGB) ?? color
        let cacheKey = cacheKey(color: drawColor, rotation: rotation)
        if let image = imageCache[cacheKey] {
            return image
        }

        // Resolve the lazy pivot before locking focus: measuring inside a
        // locked-focus context breaks the offscreen bitmap's user-space
        // scaling and yields a garbage center (glyph orbits the whole canvas).
        let pivot = glyphCenter

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        // Pivot on the glyph's optical center and land it on the canvas
        // center, so every rotation angle keeps the blades perfectly still.
        let transform = NSAffineTransform()
        transform.translateX(by: canvasSize.width / 2, yBy: canvasSize.height / 2)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -pivot.x, yBy: -pivot.y)
        transform.concat()

        if let symbol {
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
            drawColor.setFill()
            symbolRect.fill(using: .sourceAtop)
        } else {
            drawFallbackFan(in: symbolRect, color: drawColor)
        }

        image.isTemplate = false
        if imageCache.count >= imageCacheLimit {
            imageCache.removeAll(keepingCapacity: true)
        }
        imageCache[cacheKey] = image
        return image
    }

    private static func cacheKey(color: NSColor, rotation: CGFloat) -> String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let roundedRotation = Int(rotation.rounded())
        return [
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded()),
            Int((alpha * 255).rounded()),
            roundedRotation,
        ]
        .map(String.init)
        .joined(separator: ":")
    }

    /// Renders the unrotated glyph once into an offscreen bitmap and returns
    /// the center of its opaque bounding box in canvas points.
    private static func measuredGlyphCenter() -> NSPoint? {
        guard let symbol else { return nil }

        let scale: CGFloat = 8
        let pixelSize = Int(canvasSize.width * scale)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSize,
                pixelsHigh: pixelSize,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Scale user space explicitly; relying on rep.size-based scaling is
        // fragile depending on the surrounding graphics-context state.
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: scale)
        scaleTransform.concat()
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return nil }
        let bytesPerRow = rep.bytesPerRow
        let samplesPerPixel = rep.samplesPerPixel
        let alphaIndex = samplesPerPixel - 1

        var minX = pixelSize
        var maxX = -1
        var minY = pixelSize
        var maxY = -1
        for y in 0..<pixelSize {
            let row = data + y * bytesPerRow
            for x in 0..<pixelSize where row[x * samplesPerPixel + alphaIndex] > 24 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // Bitmap rows run top-down while the drawing context is bottom-up.
        let centerX = CGFloat(minX + maxX + 1) / 2 / scale
        let centerY = canvasSize.height - CGFloat(minY + maxY + 1) / 2 / scale

        // The optical center can only sit near the canvas center (baseline
        // padding is ~1pt); anything farther means the measurement context
        // was broken, and the canvas-center fallback beats a wild pivot.
        guard abs(centerX - canvasSize.width / 2) < 3, abs(centerY - canvasSize.height / 2) < 3 else {
            return nil
        }
        return NSPoint(x: centerX, y: centerY)
    }

    private static func drawFallbackFan(in rect: NSRect, color: NSColor) {
        color.setFill()
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
