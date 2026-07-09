import AppKit
import SwiftUI

extension NSColor {
    convenience init?(hexString: String) {
        var source = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if source.hasPrefix("#") {
            source.removeFirst()
        }
        guard source.count == 6, let value = UInt32(source, radix: 16) else {
            return nil
        }
        let red = CGFloat((value >> 16) & 0xff) / 255.0
        let green = CGFloat((value >> 8) & 0xff) / 255.0
        let blue = CGFloat(value & 0xff) / 255.0
        self.init(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

extension Color {
    init(hexString: String) {
        self.init(nsColor: NSColor(hexString: hexString) ?? .labelColor)
    }
}
