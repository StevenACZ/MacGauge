import Foundation
import SwiftUI

enum PopoverLayout {
    static let width: CGFloat = 360
    static let modeTransitionDuration: TimeInterval = 0.28

    static var modeTransitionAnimation: Animation {
        .spring(response: modeTransitionDuration, dampingFraction: 0.86)
    }
}
