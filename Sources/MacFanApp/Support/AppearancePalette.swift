import AppKit
import SwiftUI

enum AppearancePalette {
    /// Luminance ceiling in light appearance: 4.5:1 against a white backdrop.
    private static let lightLuminanceCeiling: Double = 0.18
    /// An achromatic tint mirrors white-on-dark, so it lands near label black.
    private static let achromaticLightLuminance: Double = 0.04
    private static let achromaticSaturationLimit: CGFloat = 0.1
    /// Luminance floor for tints on a white-glyph menu bar: macOS 26 draws the
    /// bar straight on the wallpaper, so dark tints vanish on mid-tone photos.
    private static let darkMenuBarLuminanceFloor: Double = 0.42

    static let menuBarChartPlate = dynamic(light: Color.black.opacity(0.1), dark: Color.black.opacity(0.3))
    static let menuBarHalo = dynamic(light: Color.white.opacity(0.7), dark: Color.black.opacity(0.55))

    static let processBarTrack = dynamic(light: Color.primary.opacity(0.16), dark: Color.primary.opacity(0.07))
    static let sliderKnobStroke = dynamic(light: Color.black.opacity(0.22), dark: Color.black.opacity(0.08))
    static let curveHandleStroke = dynamic(light: Color.black.opacity(0.28), dark: Color.white.opacity(0.85))
    static let curveMarkerStroke = dynamic(light: Color.black.opacity(0.24), dark: Color.white.opacity(0.72))

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    static func lightAdapted(_ color: Color) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                var resolved = NSColor.labelColor
                appearance.performAsCurrentDrawingAppearance {
                    let base = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
                    resolved = isDark(appearance) ? base : lightVariant(of: base)
                }
                return resolved
            }
        )
    }

    /// Menu bar content sits on the wallpaper, not on a window background:
    /// tints are lifted on a white-glyph bar and darkened on a black-glyph one.
    static func menuBarAdapted(_ color: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                menuBarVariant(of: color, isDark: isDark(appearance))
            }
        )
    }

    static func menuBarVariant(of color: NSColor, isDark: Bool) -> NSColor {
        isDark ? darkMenuBarVariant(of: color) : lightVariant(of: color)
    }

    static func dynamic(light: Color, dark: Color) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                var resolved = NSColor.labelColor
                appearance.performAsCurrentDrawingAppearance {
                    resolved = NSColor(isDark(appearance) ? dark : light)
                }
                return resolved
            }
        )
    }

    static func darkMenuBarVariant(of color: NSColor) -> NSColor {
        guard let base = color.usingColorSpace(.sRGB) else { return color }
        let luminance = relativeLuminance(of: base)
        guard luminance < darkMenuBarLuminanceFloor else { return base }
        let mix = (darkMenuBarLuminanceFloor - luminance) / (1 - luminance)
        func lifted(_ component: CGFloat) -> CGFloat {
            let linear = decode(component)
            return encode(linear + (1 - linear) * mix)
        }
        return NSColor(
            srgbRed: lifted(base.redComponent),
            green: lifted(base.greenComponent),
            blue: lifted(base.blueComponent),
            alpha: base.alphaComponent
        )
    }

    static func lightVariant(of color: NSColor) -> NSColor {
        guard let base = color.usingColorSpace(.sRGB) else { return color }
        let ceiling =
            base.saturationComponent < achromaticSaturationLimit
            ? achromaticLightLuminance : lightLuminanceCeiling
        let luminance = relativeLuminance(of: base)
        guard luminance > ceiling else { return base }
        let factor = ceiling / luminance
        return NSColor(
            srgbRed: encode(decode(base.redComponent) * factor),
            green: encode(decode(base.greenComponent) * factor),
            blue: encode(decode(base.blueComponent) * factor),
            alpha: base.alphaComponent
        )
    }

    static func relativeLuminance(of color: NSColor) -> Double {
        guard let base = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * decode(base.redComponent)
            + 0.7152 * decode(base.greenComponent)
            + 0.0722 * decode(base.blueComponent)
    }

    private static func decode(_ component: CGFloat) -> Double {
        let value = Double(component)
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encode(_ value: Double) -> CGFloat {
        let clamped = min(1, max(0, value))
        return CGFloat(clamped <= 0.003_130_8 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055)
    }
}
