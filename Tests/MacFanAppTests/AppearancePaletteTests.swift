import AppKit
import SwiftUI
import XCTest

@testable import MacFanApp

final class AppearancePaletteTests: XCTestCase {

    func testDarkAppearanceKeepsTheLegacyConstant() {
        let legacy = NSColor(hexString: "#FFFFFF")!
        let adapted = resolve(AppearancePalette.lightAdapted(Color(hexString: "#FFFFFF")), in: .darkAqua)

        XCTAssertEqual(adapted.redComponent, legacy.redComponent, accuracy: 0.001)
        XCTAssertEqual(adapted.greenComponent, legacy.greenComponent, accuracy: 0.001)
        XCTAssertEqual(adapted.blueComponent, legacy.blueComponent, accuracy: 0.001)
    }

    func testLightAppearanceDiffersFromDark() {
        let color = AppearancePalette.lightAdapted(Color(hexString: "#FFFFFF"))

        XCTAssertNotEqual(resolve(color, in: .aqua), resolve(color, in: .darkAqua))
    }

    func testChromaticLightVariantsCarryContrastAgainstWhite() {
        for hex in ["#FF9500", "#FF453A", "#32D74B", "#0A84FF"] {
            let light = AppearancePalette.lightVariant(of: NSColor(hexString: hex)!)
            XCTAssertLessThanOrEqual(AppearancePalette.relativeLuminance(of: light), 0.19, hex)
            XCTAssertGreaterThan(AppearancePalette.relativeLuminance(of: light), 0.05, hex)
        }
    }

    func testAchromaticLightVariantsLandNearLabelBlack() {
        for hex in ["#FFFFFF", "#F2F2F2", "#B0B0B0"] {
            let light = AppearancePalette.lightVariant(of: NSColor(hexString: hex)!)
            XCTAssertLessThanOrEqual(AppearancePalette.relativeLuminance(of: light), 0.05, hex)
        }
    }

    func testAlreadyDarkColorsAreLeftAlone() {
        let base = NSColor(hexString: "#0A2E4D")!
        let light = AppearancePalette.lightVariant(of: base)

        XCTAssertEqual(light.redComponent, base.redComponent, accuracy: 0.001)
        XCTAssertEqual(light.blueComponent, base.blueComponent, accuracy: 0.001)
    }

    func testExplicitPairResolvesPerAppearance() {
        let pair = AppearancePalette.dynamic(light: .black, dark: .white)

        XCTAssertEqual(AppearancePalette.relativeLuminance(of: resolve(pair, in: .aqua)), 0, accuracy: 0.01)
        XCTAssertEqual(AppearancePalette.relativeLuminance(of: resolve(pair, in: .darkAqua)), 1, accuracy: 0.01)
    }

    private func resolve(_ color: Color, in appearanceName: NSAppearance.Name) -> NSColor {
        let appearance = NSAppearance(named: appearanceName)!
        var resolved = NSColor.clear
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        }
        return resolved
    }
}
