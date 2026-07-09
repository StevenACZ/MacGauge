import SwiftUI

/// One metric's scrolling sparkline: gradient fill plus a stroked crest line.
/// Values morph between ticks via `SparklineShape`, which reads as the chart
/// flowing right to left. Shared by the menu bar modules and detail popovers.
struct SparklineChart: View {
    let values: [Double]
    let capacity: Int
    let peak: Double
    let color: Color
    var fillOpacity: Double = 0.32
    var lineWidth: Double = 1.5
    let tickSeconds: Double
    /// Whether new samples slide in over the tick. The slide runs almost the
    /// whole tick, so a chart that is always receiving samples is effectively
    /// always animating — menu bar charts pass false in Efficient mode and
    /// step once per tick instead.
    var animated: Bool = true

    var body: some View {
        let newestFirst = [Double](values.reversed())

        ZStack {
            SparklineShape(
                vector: AnimatableValues(values: newestFirst),
                peak: peak,
                capacity: capacity,
                closesToBaseline: true
            )
            .fill(
                LinearGradient(
                    colors: [color.opacity(fillOpacity), color.opacity(0.03)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            SparklineShape(
                vector: AnimatableValues(values: newestFirst),
                peak: peak,
                capacity: capacity,
                closesToBaseline: false
            )
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .animation(animated ? .linear(duration: min(1, max(0.3, tickSeconds * 0.85))) : nil, value: values)
        .allowsHitTesting(false)
    }
}

/// Newest-first samples anchored to the right edge; interpolating each slot
/// toward the value sliding into it produces the leftward-flow animation.
struct SparklineShape: Shape {
    var vector: AnimatableValues
    var peak: Double
    let capacity: Int
    let closesToBaseline: Bool

    var animatableData: AnimatablePair<AnimatableValues, Double> {
        get { AnimatablePair(vector, peak) }
        set {
            vector = newValue.first
            peak = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let values = vector.values
        guard values.count > 1 else { return path }

        let step = rect.width / CGFloat(max(1, capacity - 1))
        let scale = max(peak, 0.001)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.maxX - CGFloat(index) * step,
                y: rect.maxY - min(1, max(0, value / scale)) * rect.height
            )
        }

        if closesToBaseline {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// Variable-length vector so SwiftUI can interpolate the sample array between
/// ticks. Shorter operands are zero-padded at the tail (the oldest edge).
struct AnimatableValues: VectorArithmetic {
    var values: [Double]

    static var zero: AnimatableValues { AnimatableValues(values: []) }

    static func + (lhs: AnimatableValues, rhs: AnimatableValues) -> AnimatableValues {
        merged(lhs, rhs, +)
    }

    static func - (lhs: AnimatableValues, rhs: AnimatableValues) -> AnimatableValues {
        merged(lhs, rhs, -)
    }

    mutating func scale(by rhs: Double) {
        for index in values.indices {
            values[index] *= rhs
        }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }

    private static func merged(
        _ lhs: AnimatableValues,
        _ rhs: AnimatableValues,
        _ operation: (Double, Double) -> Double
    ) -> AnimatableValues {
        let count = max(lhs.values.count, rhs.values.count)
        var result = [Double](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < lhs.values.count ? lhs.values[index] : 0
            let right = index < rhs.values.count ? rhs.values[index] : 0
            result[index] = operation(left, right)
        }
        return AnimatableValues(values: result)
    }
}
