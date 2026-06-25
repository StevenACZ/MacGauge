import SwiftUI

struct CurvePreview: View {
    let points: [CurvePoint]
    let currentTemperature: Double?
    let targetPercent: Double?
    let percentRange: ClosedRange<Double>

    var body: some View {
        GeometryReader { proxy in
            let plotted = normalizedPoints(in: proxy.size)
            let marker = currentMarker(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))

                Path { path in
                    guard let first = plotted.first else { return }
                    path.move(to: first)
                    for point in plotted.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

                ForEach(Array(plotted.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(.blue)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .position(point)
                }

                if let marker {
                    let labelPosition = currentLabelPosition(for: marker, in: proxy.size)

                    Path { path in
                        path.move(to: CGPoint(x: marker.x, y: 0))
                        path.addLine(to: CGPoint(x: marker.x, y: proxy.size.height))
                    }
                    .stroke(.blue, style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))

                    Circle()
                        .fill(.blue)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.72), lineWidth: 1)
                        )
                        .position(marker)

                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.blue.opacity(0.14))
                        )
                        .position(labelPosition)
                }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .accessibilityLabel("Curve preview")
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        let sorted = points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
        guard let firstTemperature = sorted.first?.temperatureCelsius,
              let lastTemperature = sorted.last?.temperatureCelsius
        else {
            return []
        }

        let temperatureSpan = max(1, lastTemperature - firstTemperature)
        let percentSpan = max(1, percentRange.upperBound - percentRange.lowerBound)
        let plotRect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 10)
        return sorted.map { point in
            CGPoint(
                x: plotRect.minX + (point.temperatureCelsius - firstTemperature) / temperatureSpan * plotRect.width,
                y: plotRect.maxY - (clampPercent(point.percent) - percentRange.lowerBound) / percentSpan * plotRect.height
            )
        }
    }

    private func currentMarker(in size: CGSize) -> CGPoint? {
        guard let temperature = currentTemperature,
              let percent = targetPercent,
              let firstTemperature = points.map(\.temperatureCelsius).min(),
              let lastTemperature = points.map(\.temperatureCelsius).max()
        else {
            return nil
        }

        let temperatureSpan = max(1, lastTemperature - firstTemperature)
        let clampedTemperature = min(max(temperature, firstTemperature), lastTemperature)
        let percentSpan = max(1, percentRange.upperBound - percentRange.lowerBound)
        let plotRect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 10)
        return CGPoint(
            x: plotRect.minX + (clampedTemperature - firstTemperature) / temperatureSpan * plotRect.width,
            y: plotRect.maxY - (clampPercent(percent) - percentRange.lowerBound) / percentSpan * plotRect.height
        )
    }

    private func currentLabelPosition(for marker: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(marker.x + 38, 42), size.width - 42),
            y: 18
        )
    }

    private func clampPercent(_ percent: Double) -> Double {
        min(max(percent, percentRange.lowerBound), percentRange.upperBound)
    }
}
