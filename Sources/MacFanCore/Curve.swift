import Foundation

public struct FanCurve {
    public let points: [(temperature: Double, percent: Double)]

    public init(points: [(Double, Double)]) throws {
        guard points.count >= 2 else {
            throw MacFanError("A curve needs at least two points, for example 40:40,60:50.")
        }

        let sorted = points.sorted { $0.0 < $1.0 }
        for point in sorted {
            guard point.0.isFinite, point.1.isFinite else {
                throw MacFanError("Curve points must be finite numbers.")
            }
            guard point.1 >= 0, point.1 <= 100 else {
                throw MacFanError("Curve percent \(point.1) is outside 0...100.")
            }
        }
        for index in 1..<sorted.count {
            guard abs(sorted[index].0 - sorted[index - 1].0) >= 0.001 else {
                throw MacFanError("Curve point temperatures must be unique.")
            }
        }

        self.points = sorted.map { (temperature: $0.0, percent: $0.1) }
    }

    public func percent(for temperature: Double) -> Double {
        if temperature <= points[0].temperature {
            return points[0].percent
        }

        for index in 1..<points.count {
            let previous = points[index - 1]
            let next = points[index]
            guard temperature <= next.temperature else { continue }
            let span = next.temperature - previous.temperature
            guard span > 0 else { return next.percent }
            let progress = (temperature - previous.temperature) / span
            return previous.percent + progress * (next.percent - previous.percent)
        }

        return points[points.count - 1].percent
    }

    public static func parse(_ raw: String?) throws -> FanCurve {
        let source = raw ?? "40:40,60:50"
        let points = try source.split(separator: ",").map { item -> (Double, Double) in
            let pieces = item.split(separator: ":")
            guard pieces.count == 2,
                let temperature = Double(pieces[0].trimmingCharacters(in: .whitespaces)),
                let percent = Double(pieces[1].trimmingCharacters(in: .whitespaces))
            else {
                throw MacFanError("Invalid curve point '\(item)'. Use temp:percent, for example 40:40,60:50.")
            }
            return (temperature, percent)
        }
        return try FanCurve(points: points)
    }
}
