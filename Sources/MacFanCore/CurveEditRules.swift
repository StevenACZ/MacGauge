import Foundation

/// Pure math for the curve editor: clamping, ordering, and the 1°C minimum
/// separation between points, plus where a newly added point should land.
public enum CurveEditRules {
    public static func normalized(
        _ points: [(temperature: Double, percent: Double)],
        temperatureRange: ClosedRange<Double>
    ) -> [(temperature: Double, percent: Double)] {
        guard !points.isEmpty else { return points }

        var sorted =
            points
            .map { point in
                (
                    temperature: min(max(point.temperature, temperatureRange.lowerBound), temperatureRange.upperBound)
                        .rounded(),
                    percent: min(max(point.percent, 0), 100).rounded()
                )
            }
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.temperature == rhs.element.temperature {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.temperature < rhs.element.temperature
            }
            .map(\.element)

        guard sorted.count > 1 else { return sorted }

        for index in sorted.indices.dropFirst() {
            let minimum = sorted[index - 1].temperature + 1
            if sorted[index].temperature < minimum {
                sorted[index].temperature = min(temperatureRange.upperBound, minimum)
            }
        }

        for index in sorted.indices.dropLast().reversed() {
            let maximum = sorted[index + 1].temperature - 1
            if sorted[index].temperature > maximum {
                sorted[index].temperature = max(temperatureRange.lowerBound, maximum)
            }
        }

        return sorted
    }

    public static func insertionPoint(
        sortedPoints: [(temperature: Double, percent: Double)],
        temperatureRange: ClosedRange<Double>
    ) -> (temperature: Double, percent: Double) {
        if let gap = largestTemperatureGap(in: sortedPoints), gap.width >= 2 {
            return (
                temperature: (gap.lower.temperature + gap.upper.temperature) / 2,
                percent: (gap.lower.percent + gap.upper.percent) / 2
            )
        }

        let temperature = min(temperatureRange.upperBound, (sortedPoints.last?.temperature ?? 60) + 10)
        let percent = min(90, (sortedPoints.last?.percent ?? 50) + 10)
        return (temperature: temperature, percent: percent)
    }

    private static func largestTemperatureGap(
        in points: [(temperature: Double, percent: Double)]
    ) -> (lower: (temperature: Double, percent: Double), upper: (temperature: Double, percent: Double), width: Double)? {
        guard points.count >= 2 else { return nil }
        return zip(points, points.dropFirst())
            .map { lower, upper in (lower: lower, upper: upper, width: upper.temperature - lower.temperature) }
            .max { $0.width < $1.width }
    }
}
