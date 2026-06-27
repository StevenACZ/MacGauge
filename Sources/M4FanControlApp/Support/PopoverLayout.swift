import Foundation
import SwiftUI

enum PopoverLayout {
    static let width: CGFloat = 360
    static let manualHeight: CGFloat = 232
    static let curveHeight: CGFloat = 383
    static let modeTransitionDuration: TimeInterval = 0.28

    static func height(for mode: FanControlMode) -> CGFloat {
        switch mode {
        case .manual:
            return manualHeight
        case .curve:
            return curveHeight
        }
    }

    static var modeTransitionAnimation: Animation {
        .easeInOut(duration: modeTransitionDuration)
    }
}
