import SwiftUI

struct CurvePreview: View {
    let points: [CurvePoint]
    let currentTemperature: Double?
    let targetPercent: Double?
    let percentRange: ClosedRange<Double>
    let isEditingEnabled: Bool
    let animatesLiveMarker: Bool
    let updatePoint: (CurvePoint) -> Void

    init(
        points: [CurvePoint],
        currentTemperature: Double?,
        targetPercent: Double?,
        percentRange: ClosedRange<Double>,
        isEditingEnabled: Bool,
        animatesLiveMarker: Bool = false,
        updatePoint: @escaping (CurvePoint) -> Void
    ) {
        self.points = points
        self.currentTemperature = currentTemperature
        self.targetPercent = targetPercent
        self.percentRange = percentRange
        self.isEditingEnabled = isEditingEnabled
        self.animatesLiveMarker = animatesLiveMarker
        self.updatePoint = updatePoint
    }

    var body: some View {
        GeometryReader { proxy in
            let plotted = normalizedPoints(in: proxy.size)
            let marker = currentMarker(in: proxy.size)
            let plotRect = plotRect(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))

                ForEach(axisTicks, id: \.self) { tick in
                    Path { path in
                        let x = xPosition(forTemperature: tick, in: plotRect)
                        path.move(to: CGPoint(x: x, y: plotRect.minY))
                        path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
                    }
                    .stroke(Color.primary.opacity(tick == 0 || tick == 100 ? 0.18 : 0.09), lineWidth: 0.8)

                    Text("\(Int(tick))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: xAxisLabelX(for: tick, plotRect: plotRect, viewWidth: proxy.size.width), y: plotRect.maxY + CurvePreviewLayout.xAxisLabelOffset)
                }

                ForEach(axisTicks, id: \.self) { tick in
                    Path { path in
                        let y = yPosition(forPercent: tick, in: plotRect)
                        path.move(to: CGPoint(x: plotRect.minX, y: y))
                        path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                    }
                    .stroke(Color.primary.opacity(tick == 0 || tick == 100 ? 0.18 : 0.09), lineWidth: 0.8)

                    Text("\(Int(tick))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .position(x: plotRect.minX - 20, y: yPosition(forPercent: tick, in: plotRect))
                }

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

                ForEach(sortedPoints) { point in
                    Circle()
                        .fill(Color.accentColor.opacity(isEditingEnabled ? 0.92 : 0.45))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.82), lineWidth: 1.4)
                        )
                        .shadow(color: .black.opacity(isEditingEnabled ? 0.22 : 0), radius: 2, y: 1)
                        .position(position(for: point, in: proxy.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isEditingEnabled else { return }
                                    updatePoint(point.moved(to: value.location, in: proxy.size, percentRange: percentRange))
                                }
                        )
                        .help(isEditingEnabled ? "Drag curve point" : "Curve point")
                        .accessibilityLabel("Curve point")
                        .accessibilityValue("\(Int(point.temperatureCelsius.rounded())) C, \(Int(point.percent.rounded())) percent")
                }

                if let marker {
                    Path { path in
                        path.move(to: CGPoint(x: marker.x, y: plotRect.minY))
                        path.addLine(to: CGPoint(x: marker.x, y: plotRect.maxY))
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
                }
            }
            .animation(animatesLiveMarker ? .easeOut(duration: 0.28) : nil, value: liveMarkerAnimationKey)
            .transaction { transaction in
                if !animatesLiveMarker {
                    transaction.animation = nil
                }
            }
        }
        .accessibilityLabel("Curve preview")
    }

    private var sortedPoints: [CurvePoint] {
        points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
    }

    private var axisTicks: [Double] {
        [0, 25, 50, 75, 100]
    }

    private var liveMarkerAnimationKey: String {
        guard let currentTemperature, let targetPercent else { return "none" }
        return String(format: "%.1f-%.1f", currentTemperature, targetPercent)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        sortedPoints.map { position(for: $0, in: size) }
    }

    private func currentMarker(in size: CGSize) -> CGPoint? {
        guard let temperature = currentTemperature,
              let percent = targetPercent
        else {
            return nil
        }

        let temperatureRange = CurvePoint.temperatureRange
        let temperatureSpan = max(1, temperatureRange.upperBound - temperatureRange.lowerBound)
        let clampedTemperature = min(max(temperature, temperatureRange.lowerBound), temperatureRange.upperBound)
        let plotRect = plotRect(in: size)
        return CGPoint(
            x: plotRect.minX + (clampedTemperature - temperatureRange.lowerBound) / temperatureSpan * plotRect.width,
            y: yPosition(forPercent: clampPercent(percent), in: plotRect)
        )
    }

    private func position(for point: CurvePoint, in size: CGSize) -> CGPoint {
        let temperatureRange = CurvePoint.temperatureRange
        let temperatureSpan = max(1, temperatureRange.upperBound - temperatureRange.lowerBound)
        let plotRect = plotRect(in: size)
        let temperature = min(max(point.temperatureCelsius, temperatureRange.lowerBound), temperatureRange.upperBound)

        return CGPoint(
            x: plotRect.minX + (temperature - temperatureRange.lowerBound) / temperatureSpan * plotRect.width,
            y: yPosition(forPercent: clampPercent(point.percent), in: plotRect)
        )
    }

    private func clampPercent(_ percent: Double) -> Double {
        min(max(percent, 0), 100)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        curvePreviewPlotRect(in: size)
    }

    private func xPosition(forTemperature temperature: Double, in plotRect: CGRect) -> CGFloat {
        let range = CurvePoint.temperatureRange
        let progress = (temperature - range.lowerBound) / max(1, range.upperBound - range.lowerBound)
        return plotRect.minX + progress * plotRect.width
    }

    private func xAxisLabelX(for tick: Double, plotRect: CGRect, viewWidth: CGFloat) -> CGFloat {
        let x = xPosition(forTemperature: tick, in: plotRect)
        if tick >= 100 {
            return min(x, viewWidth - 14)
        }
        if tick <= 0 {
            return max(x, 14)
        }
        return x
    }

    private func yPosition(forPercent percent: Double, in plotRect: CGRect) -> CGFloat {
        let progress = min(max(percent, 0), 100) / 100
        return plotRect.maxY - progress * plotRect.height
    }
}

private extension CurvePoint {
    func moved(to location: CGPoint, in size: CGSize, percentRange: ClosedRange<Double>) -> CurvePoint {
        let plotRect = curvePreviewPlotRect(in: size)
        let clampedX = min(max(location.x, plotRect.minX), plotRect.maxX)
        let clampedY = min(max(location.y, plotRect.minY), plotRect.maxY)
        let temperatureRange = CurvePoint.temperatureRange
        let temperatureProgress = plotRect.width > 0 ? (clampedX - plotRect.minX) / plotRect.width : 0
        let percentProgress = plotRect.height > 0 ? (plotRect.maxY - clampedY) / plotRect.height : 0
        let temperature = temperatureRange.lowerBound + temperatureProgress * (temperatureRange.upperBound - temperatureRange.lowerBound)
        let rawPercent = percentProgress * 100
        let percent = min(max(rawPercent, percentRange.lowerBound), percentRange.upperBound)

        return CurvePoint(
            id: id,
            temperatureCelsius: temperature.rounded(),
            percent: percent.rounded()
        )
    }
}

private enum CurvePreviewLayout {
    static let leadingInset: CGFloat = 42
    static let trailingInset: CGFloat = 18
    static let plotTopPadding: CGFloat = 22
    static let plotBottomPadding: CGFloat = 12
    static let xAxisLabelBand: CGFloat = 15
    static let xAxisLabelOffset: CGFloat = 12
}

private func curvePreviewPlotRect(in size: CGSize) -> CGRect {
    let topInset = CurvePreviewLayout.plotTopPadding
    let bottomInset = CurvePreviewLayout.plotBottomPadding + CurvePreviewLayout.xAxisLabelBand

    return CGRect(
        x: CurvePreviewLayout.leadingInset,
        y: topInset,
        width: max(1, size.width - CurvePreviewLayout.leadingInset - CurvePreviewLayout.trailingInset),
        height: max(1, size.height - topInset - bottomInset)
    )
}
