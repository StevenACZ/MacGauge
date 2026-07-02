import SwiftUI

/// Central design tokens: colors, layout metrics, and the two spring
/// families used across the app (fast feedback vs. content motion).
enum Theme {
    static let accent = Color(nsColor: .systemTeal)
    static let accentGradient = LinearGradient(
        colors: [.teal, .cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Layout {
        static let panelWidth: CGFloat = 360
        static let cardRadius: CGFloat = 12
        static let rowRadius: CGFloat = 8
        static let badgeRadius: CGFloat = 6
        static let cardFill = Color.primary.opacity(0.04)
        static let cardStroke = Color.primary.opacity(0.08)
    }

    enum Anim {
        /// State changes and general UI feedback.
        static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)
        /// Hover and press micro-interactions.
        static let hover = Animation.spring(response: 0.2, dampingFraction: 0.7)
        /// Content that moves or resizes (lists, reveals).
        static let content = Animation.spring(duration: 0.35, bounce: 0.15)
        /// Conditional-row reveals in settings.
        static let smooth = Animation.smooth(duration: 0.25)
        static let easeOut = Animation.easeOut(duration: 0.2)
        /// Popover mode/content transitions.
        static let mode = Animation.spring(response: 0.28, dampingFraction: 0.86)
    }
}
