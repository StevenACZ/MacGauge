import Foundation

struct CurvePoint: Codable, Equatable, Identifiable {
    var id: UUID
    var temperatureCelsius: Double
    var percent: Double

    init(id: UUID = UUID(), temperatureCelsius: Double, percent: Double) {
        self.id = id
        self.temperatureCelsius = temperatureCelsius
        self.percent = percent
    }
}
