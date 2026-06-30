import Foundation
import SwiftUI

enum PopoverLayout {
    static let width: CGFloat = 360
    static let manualHeight: CGFloat = 230
    static let curveHeight: CGFloat = 381
    static let contestedBannerHeight: CGFloat = 36
    static let modeTransitionDuration: TimeInterval = 0.28

    static func height(for mode: FanControlMode, contested: Bool = false) -> CGFloat {
        let base: CGFloat
        switch mode {
        case .manual:
            base = manualHeight
        case .curve:
            base = curveHeight
        }
        return base + (contested ? contestedBannerHeight : 0)
    }

    static var modeTransitionAnimation: Animation {
        .easeInOut(duration: modeTransitionDuration)
    }
}
