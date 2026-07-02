import Foundation
import MacFanCore

@MainActor
final class AppSettingsStore: ObservableObject {
    private enum Key {
        static let temperatureUnit = "temperatureUnit"
        static let controlMode = "controlMode"
        static let manualPercent = "manualPercent"
        static let curvePoints = "curvePoints"
        static let restoreAutomaticOnQuit = "restoreAutomaticOnQuit"
        static let dangerousRangesUnlocked = "dangerousRangesUnlocked"
        static let normalUpperCelsius = "normalUpperCelsius"
        static let hotLowerCelsius = "hotLowerCelsius"
        static let normalColorHex = "normalColorHex"
        static let mediumColorHex = "mediumColorHex"
        static let hotColorHex = "hotColorHex"
        static let animateFanIcon = "animateFanIcon"
        static let controlTickSeconds = "controlTickSeconds"
    }

    static let controlTickRange: ClosedRange<Double> = 0.5...10

    private let defaults: UserDefaults

    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }

    @Published var controlMode: FanControlMode {
        didSet { defaults.set(controlMode.rawValue, forKey: Key.controlMode) }
    }

    @Published var manualPercent: Double {
        didSet { defaults.set(manualPercent, forKey: Key.manualPercent) }
    }

    @Published var curvePoints: [CurvePoint] {
        didSet { saveCurvePoints() }
    }

    @Published var restoreAutomaticOnQuit: Bool {
        didSet { defaults.set(restoreAutomaticOnQuit, forKey: Key.restoreAutomaticOnQuit) }
    }

    @Published var dangerousRangesUnlocked: Bool {
        didSet { defaults.set(dangerousRangesUnlocked, forKey: Key.dangerousRangesUnlocked) }
    }

    @Published var normalUpperCelsius: Double {
        didSet { defaults.set(normalUpperCelsius, forKey: Key.normalUpperCelsius) }
    }

    @Published var hotLowerCelsius: Double {
        didSet { defaults.set(hotLowerCelsius, forKey: Key.hotLowerCelsius) }
    }

    @Published var normalColorHex: String {
        didSet { defaults.set(normalColorHex, forKey: Key.normalColorHex) }
    }

    @Published var mediumColorHex: String {
        didSet { defaults.set(mediumColorHex, forKey: Key.mediumColorHex) }
    }

    @Published var hotColorHex: String {
        didSet { defaults.set(hotColorHex, forKey: Key.hotColorHex) }
    }

    @Published var animateFanIcon: Bool {
        didSet { defaults.set(animateFanIcon, forKey: Key.animateFanIcon) }
    }

    @Published var controlTickSeconds: Double {
        didSet { defaults.set(Self.clampedControlTick(controlTickSeconds), forKey: Key.controlTickSeconds) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.temperatureUnit) ?? "") ?? .celsius
        controlMode = FanControlMode(rawValue: defaults.string(forKey: Key.controlMode) ?? "") ?? .manual

        let storedPercent = defaults.object(forKey: Key.manualPercent) as? Double
        manualPercent = storedPercent ?? 45

        curvePoints = Self.loadCurvePoints(defaults: defaults)

        if defaults.object(forKey: Key.restoreAutomaticOnQuit) == nil {
            restoreAutomaticOnQuit = true
        } else {
            restoreAutomaticOnQuit = defaults.bool(forKey: Key.restoreAutomaticOnQuit)
        }

        dangerousRangesUnlocked = defaults.bool(forKey: Key.dangerousRangesUnlocked)

        normalUpperCelsius = defaults.object(forKey: Key.normalUpperCelsius) as? Double ?? 45
        hotLowerCelsius = defaults.object(forKey: Key.hotLowerCelsius) as? Double ?? 70
        normalColorHex = defaults.string(forKey: Key.normalColorHex) ?? "#FFFFFF"
        mediumColorHex = defaults.string(forKey: Key.mediumColorHex) ?? "#FF9500"
        hotColorHex = defaults.string(forKey: Key.hotColorHex) ?? "#FF453A"

        if defaults.object(forKey: Key.animateFanIcon) == nil {
            animateFanIcon = true
        } else {
            animateFanIcon = defaults.bool(forKey: Key.animateFanIcon)
        }

        let storedTick = defaults.object(forKey: Key.controlTickSeconds) as? Double
        controlTickSeconds = Self.clampedControlTick(storedTick ?? 1)
    }

    var curveCommandPoints: String {
        curvePoints
            .sorted { $0.temperatureCelsius < $1.temperatureCelsius }
            .map { point in
                "\(Int(point.temperatureCelsius.rounded())):\(Int(point.percent.rounded()))"
            }
            .joined(separator: ",")
    }

    var curve: FanCurve? {
        try? FanCurve(points: curvePoints.map { ($0.temperatureCelsius, $0.percent) })
    }

    var visualRules: TemperatureVisualRules {
        TemperatureVisualRules(normalUpperCelsius: normalUpperCelsius, hotLowerCelsius: hotLowerCelsius)
    }

    func addCurvePoint() {
        let sorted = curvePoints.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        let newPoint: CurvePoint

        if let gap = largestTemperatureGap(in: sorted), gap.width >= 2 {
            newPoint = CurvePoint(
                temperatureCelsius: (gap.lower.temperatureCelsius + gap.upper.temperatureCelsius) / 2,
                percent: (gap.lower.percent + gap.upper.percent) / 2
            )
        } else {
            let nextTemperature = min(CurvePoint.temperatureRange.upperBound, (sorted.last?.temperatureCelsius ?? 60) + 10)
            let nextPercent = min(90, (sorted.last?.percent ?? 50) + 10)
            newPoint = CurvePoint(temperatureCelsius: nextTemperature, percent: nextPercent)
        }

        curvePoints = Self.normalizedCurvePoints(sorted + [newPoint])
    }

    func addCurvePoint(temperatureCelsius: Double, percent: Double) {
        let range = CurvePoint.temperatureRange
        let point = CurvePoint(
            temperatureCelsius: min(max(temperatureCelsius, range.lowerBound), range.upperBound).rounded(),
            percent: min(max(percent, 0), 100).rounded()
        )
        curvePoints = Self.normalizedCurvePoints(curvePoints + [point])
    }

    func removeCurvePoints(at offsets: IndexSet) {
        guard curvePoints.count - offsets.count >= 2 else { return }
        curvePoints.remove(atOffsets: offsets)
    }

    func removeCurvePoint(id: UUID) {
        guard curvePoints.count > 2 else { return }
        curvePoints.removeAll { $0.id == id }
    }

    func updateCurvePoint(_ point: CurvePoint) {
        guard let index = curvePoints.firstIndex(where: { $0.id == point.id }) else { return }
        var next = curvePoints
        next[index] = point
        curvePoints = Self.normalizedCurvePoints(next)
    }

    func resetCurveDefaults() {
        curvePoints = Self.defaultCurvePoints
    }

    func saveCurvePoints() {
        guard let data = try? JSONEncoder().encode(curvePoints) else { return }
        defaults.set(data, forKey: Key.curvePoints)
    }

    private static func loadCurvePoints(defaults: UserDefaults) -> [CurvePoint] {
        guard let data = defaults.data(forKey: Key.curvePoints),
            let decoded = try? JSONDecoder().decode([CurvePoint].self, from: data),
            decoded.count >= 2
        else {
            return defaultCurvePoints
        }
        return normalizedCurvePoints(decoded)
    }

    private static var defaultCurvePoints: [CurvePoint] {
        [
            CurvePoint(temperatureCelsius: 40, percent: 40),
            CurvePoint(temperatureCelsius: 60, percent: 50),
            CurvePoint(temperatureCelsius: 80, percent: 80),
        ]
    }

    private static func clampedControlTick(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 1 }
        return min(max(seconds, controlTickRange.lowerBound), controlTickRange.upperBound)
    }

    private static func normalizedCurvePoints(_ points: [CurvePoint]) -> [CurvePoint] {
        guard !points.isEmpty else { return points }

        var sorted =
            points
            .map { point in
                CurvePoint(
                    id: point.id,
                    temperatureCelsius: rounded(
                        min(max(point.temperatureCelsius, CurvePoint.temperatureRange.lowerBound), CurvePoint.temperatureRange.upperBound)
                    ),
                    percent: rounded(min(max(point.percent, 0), 100))
                )
            }
            .sorted { lhs, rhs in
                if lhs.temperatureCelsius == rhs.temperatureCelsius {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.temperatureCelsius < rhs.temperatureCelsius
            }

        guard sorted.count > 1 else { return sorted }

        for index in sorted.indices.dropFirst() {
            let minimum = sorted[sorted.index(before: index)].temperatureCelsius + 1
            if sorted[index].temperatureCelsius < minimum {
                sorted[index].temperatureCelsius = min(CurvePoint.temperatureRange.upperBound, minimum)
            }
        }

        for index in sorted.indices.dropLast().reversed() {
            let maximum = sorted[sorted.index(after: index)].temperatureCelsius - 1
            if sorted[index].temperatureCelsius > maximum {
                sorted[index].temperatureCelsius = max(CurvePoint.temperatureRange.lowerBound, maximum)
            }
        }

        return sorted
    }

    private static func rounded(_ value: Double) -> Double {
        value.rounded()
    }

    private func largestTemperatureGap(in points: [CurvePoint]) -> (lower: CurvePoint, upper: CurvePoint, width: Double)? {
        guard points.count >= 2 else { return nil }
        return zip(points, points.dropFirst())
            .map { lower, upper in (lower: lower, upper: upper, width: upper.temperatureCelsius - lower.temperatureCelsius) }
            .max { $0.width < $1.width }
    }
}
