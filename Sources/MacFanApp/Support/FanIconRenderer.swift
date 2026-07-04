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
    /// The glyph is rasterized once at this multiple of canvas points; frames
    /// only rotate and downsample that sprite, so blades stay crisp.
    private static let spriteScale: CGFloat = 4
    /// Menu bar backing density. A single 2x rep also downsamples cleanly on
    /// non-retina displays.
    private static let outputScale: CGFloat = 2

    private static let symbol: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        return ["fanblades.fill", "fanblades", "fan.fill", "fan"]
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: "MacGauge") }
            .compactMap { $0.withSymbolConfiguration(configuration) }
            .first
    }()

    /// Fan glyph baked once into a fixed high-resolution bitmap, plus its
    /// alpha-weighted centroid in sprite pixels. Re-rendering the vector
    /// symbol per angle lets AppKit re-rasterize it against a slightly
    /// different pixel grid on some angles, which reads as the icon jumping
    /// 1-2 px in the menu bar; rotating one fixed bitmap is continuous in the
    /// angle. The centroid is the rotation-invariant center of the blades —
    /// SF Symbol canvases carry baseline padding, so neither the canvas
    /// center nor the bounding-box center keeps them still.
    private static let sprite: (image: CGImage, pivot: CGPoint)? = bakeSprite()

    static func image(color: NSColor, rotation: CGFloat) -> NSImage? {
        guard let sprite else { return nil }
        let drawColor = color.usingColorSpace(.sRGB) ?? color
        let cacheKey = cacheKey(color: drawColor, rotation: rotation)
        if let image = imageCache[cacheKey] {
            return image
        }

        let pixelSize = Int(canvasSize.width * outputScale)
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
        rep.size = canvasSize

        let ctx = context.cgContext
        let deviceRect = CGRect(x: 0, y: 0, width: CGFloat(pixelSize), height: CGFloat(pixelSize))
        ctx.clear(deviceRect)
        ctx.interpolationQuality = .high

        // Pivot on the sprite centroid and land it on the canvas center.
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(pixelSize) / 2, y: CGFloat(pixelSize) / 2)
        ctx.rotate(by: rotation * .pi / 180)
        ctx.scaleBy(x: outputScale / spriteScale, y: outputScale / spriteScale)
        ctx.translateBy(x: -sprite.pivot.x, y: -sprite.pivot.y)
        ctx.draw(
            sprite.image,
            in: CGRect(x: 0, y: 0, width: sprite.image.width, height: sprite.image.height)
        )
        ctx.restoreGState()

        // Tint in device space; sourceAtop only touches drawn glyph pixels.
        ctx.setBlendMode(.sourceAtop)
        ctx.setFillColor(drawColor.cgColor)
        ctx.fill(deviceRect)
        ctx.flush()

        let image = NSImage(size: canvasSize)
        image.addRepresentation(rep)
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

    /// Renders the unrotated glyph once into the sprite bitmap and locates
    /// its alpha-weighted centroid in sprite pixels.
    private static func bakeSprite() -> (image: CGImage, pivot: CGPoint)? {
        let pixelSize = Int(canvasSize.width * spriteScale)
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
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
        // Scale user space explicitly; relying on rep.size-based scaling is
        // fragile depending on the surrounding graphics-context state.
        let scaleTransform = NSAffineTransform()
        scaleTransform.scale(by: spriteScale)
        scaleTransform.concat()
        if let symbol {
            symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1)
        } else {
            drawFallbackFan(in: symbolRect, color: .black)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData, let cgImage = rep.cgImage else { return nil }
        let bytesPerRow = rep.bytesPerRow
        let samplesPerPixel = rep.samplesPerPixel
        let alphaIndex = samplesPerPixel - 1

        var alphaSum = 0.0
        var xSum = 0.0
        var ySum = 0.0
        for y in 0..<pixelSize {
            let row = data + y * bytesPerRow
            for x in 0..<pixelSize {
                let alpha = Double(row[x * samplesPerPixel + alphaIndex])
                guard alpha > 0 else { continue }
                alphaSum += alpha
                xSum += alpha * (Double(x) + 0.5)
                ySum += alpha * (Double(y) + 0.5)
            }
        }
        guard alphaSum > 0 else { return nil }

        // Bitmap rows run top-down while CG draws bottom-up.
        let pivot = CGPoint(x: xSum / alphaSum, y: Double(pixelSize) - ySum / alphaSum)

        // The centroid can only sit near the sprite center (baseline padding
        // is ~1pt); anything farther means the measurement context was
        // broken, and the sprite-center fallback beats a wild pivot.
        let center = CGFloat(pixelSize) / 2
        guard abs(pivot.x - center) < 3 * spriteScale, abs(pivot.y - center) < 3 * spriteScale else {
            return (cgImage, CGPoint(x: center, y: center))
        }
        return (cgImage, pivot)
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
