import SwiftUI

struct ManualPercentSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double = 1
    var isDisabled: Bool = false

    @State private var isHovered = false
    @State private var isDragging = false

    private let trackHeight: CGFloat = 6
    private let thumbDiameter: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let centerY = proxy.size.height / 2
            let travel = max(0, totalWidth - thumbDiameter)
            let fraction = Self.fraction(of: value, in: range)
            let thumbCenter = thumbDiameter / 2 + fraction * travel

            ZStack {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: totalWidth, height: trackHeight)
                    .position(x: totalWidth / 2, y: centerY)

                Capsule()
                    .fill(Color.accentColor.opacity(isDisabled ? 0.5 : 1))
                    .frame(width: max(0, thumbCenter), height: trackHeight)
                    .position(x: thumbCenter / 2, y: centerY)

                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(
                        color: .black.opacity(isDragging ? 0.28 : 0.18),
                        radius: isDragging ? 4 : 2,
                        y: 1
                    )
                    .scaleEffect(thumbScale)
                    .animation(Theme.Anim.hover, value: thumbScale)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .position(x: thumbCenter, y: centerY)
            }
            .frame(width: totalWidth, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !isDisabled else { return }
                        isDragging = true
                        let f = max(0, min(1, (drag.location.x - thumbDiameter / 2) / max(1, travel)))
                        let raw = range.lowerBound + f * (range.upperBound - range.lowerBound)
                        value = Self.snap(raw, step: step, in: range)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(height: thumbDiameter)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Manual fan target"))
        .accessibilityValue(Text("\(Int(value.rounded())) percent"))
        .accessibilityAdjustableAction { direction in
            guard !isDisabled else { return }
            switch direction {
            case .increment:
                value = Self.snap(value + step, step: step, in: range)
            case .decrement:
                value = Self.snap(value - step, step: step, in: range)
            @unknown default:
                break
            }
        }
    }

    private var thumbScale: CGFloat {
        if isDragging { return 1.18 }
        if isHovered && !isDisabled { return 1.1 }
        return 1.0
    }

    private static func fraction(of value: Double, in range: ClosedRange<Double>) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(max(0, min(1, (value - range.lowerBound) / span)))
    }

    private static func snap(_ value: Double, step: Double, in range: ClosedRange<Double>) -> Double {
        let stepped = (value / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }
}
