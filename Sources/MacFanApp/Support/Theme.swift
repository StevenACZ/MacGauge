import SwiftUI

/// Central design tokens: colors, layout metrics, and the two spring
/// families used across the app (fast feedback vs. content motion).
enum Theme {
    static let accent = Color(nsColor: .systemTeal)

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
        /// Numeric content transitions (counters, RPM readouts).
        static let value = Animation.default
        /// The curve preview's live marker easing between ticks.
        static let liveMarker = Animation.easeOut(duration: 0.28)
        /// Decorative pulse rings; call sites add `repeatForever`.
        static let pulse = Animation.easeOut(duration: 1.3)
    }
}

/// The recurring card chrome: a rounded fill with a hairline stroke border,
/// applied as a background so each site keeps its exact radius and colors.
private struct CardChrome: ViewModifier {
    let radius: CGFloat
    let fill: Color
    let stroke: Color

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(stroke, lineWidth: 1)
                )
        )
    }
}

extension View {
    func cardChrome(radius: CGFloat, fill: Color, stroke: Color) -> some View {
        modifier(CardChrome(radius: radius, fill: fill, stroke: stroke))
    }
}
