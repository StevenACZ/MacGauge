import Foundation

struct CurvePoint: Codable, Equatable, Identifiable {
    static let temperatureRange: ClosedRange<Double> = 0...100

    var id: UUID
    var temperatureCelsius: Double
    var percent: Double

    init(id: UUID = UUID(), temperatureCelsius: Double, percent: Double) {
        self.id = id
        self.temperatureCelsius = temperatureCelsius
        self.percent = percent
    }
}
