import Foundation

public struct FanCurve {
    public let points: [(temperature: Double, percent: Double)]

    public init(points: [(Double, Double)]) throws {
        guard points.count >= 2 else {
            throw M4FanError("A curve needs at least two points, for example 40:40,60:50.")
        }

        let sorted = points.sorted { $0.0 < $1.0 }
        for point in sorted {
            guard point.1 >= 0, point.1 <= 100 else {
                throw M4FanError("Curve percent \(point.1) is outside 0...100.")
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
                  let temperature = Double(pieces[0]),
                  let percent = Double(pieces[1])
            else {
                throw M4FanError("Invalid curve point '\(item)'. Use temp:percent, for example 40:40,60:50.")
            }
            return (temperature, percent)
        }
        return try FanCurve(points: points)
    }
}

public enum StopFlag {
    nonisolated(unsafe) public static var shouldStop = false

    public static func installSignalHandlers() {
        signal(SIGINT) { _ in StopFlag.shouldStop = true }
        signal(SIGTERM) { _ in StopFlag.shouldStop = true }
    }
}
