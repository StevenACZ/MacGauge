import SwiftUI

struct CurvePreview: View {
    let points: [CurvePoint]
    let currentTemperature: Double?
    let targetPercent: Double?
    let percentRange: ClosedRange<Double>
    let isEditingEnabled: Bool
    let animatesLiveMarker: Bool
    let estimatedRPM: ((Double) -> Double?)?
    let currentRPM: Double?
    let updatePoint: (CurvePoint) -> Void
    let addPoint: ((_ temperatureCelsius: Double, _ percent: Double) -> Void)?
    let deletePoint: ((UUID) -> Void)?
    let canDeletePoints: Bool

    @State private var hoveredPointID: UUID?
    @State private var draggedPointID: UUID?

    init(
        points: [CurvePoint],
        currentTemperature: Double?,
        targetPercent: Double?,
        percentRange: ClosedRange<Double>,
        isEditingEnabled: Bool,
        animatesLiveMarker: Bool = false,
        estimatedRPM: ((Double) -> Double?)? = nil,
        currentRPM: Double? = nil,
        updatePoint: @escaping (CurvePoint) -> Void,
        addPoint: ((_ temperatureCelsius: Double, _ percent: Double) -> Void)? = nil,
        deletePoint: ((UUID) -> Void)? = nil,
        canDeletePoints: Bool = false
    ) {
        self.points = points
        self.currentTemperature = currentTemperature
        self.targetPercent = targetPercent
        self.percentRange = percentRange
        self.isEditingEnabled = isEditingEnabled
        self.animatesLiveMarker = animatesLiveMarker
        self.estimatedRPM = estimatedRPM
        self.currentRPM = currentRPM
        self.updatePoint = updatePoint
        self.addPoint = addPoint
        self.deletePoint = deletePoint
        self.canDeletePoints = canDeletePoints
    }

    var body: some View {
        GeometryReader { proxy in
            let plotRect = plotRect(in: proxy.size)
            let plotted = extendedToPlotEdges(normalizedPoints(in: proxy.size), plotRect: plotRect)
            let marker = currentMarker(in: proxy.size)

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .gesture(doubleClickToAdd(in: proxy.size), including: addPoint == nil ? .none : .all)

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
                        .position(
                            x: xAxisLabelX(for: tick, plotRect: plotRect, viewWidth: proxy.size.width),
                            y: plotRect.maxY + CurvePreviewLayout.xAxisLabelOffset)
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

                if let rpmAxisValues {
                    ForEach(Array(zip(axisTicks, rpmAxisValues)), id: \.0) { pair in
                        Text(AppFormatters.compactRPM(pair.1))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .position(
                                x: plotRect.maxX + CurvePreviewLayout.rpmAxisLabelOffset,
                                y: yPosition(forPercent: pair.0, in: plotRect))
                    }

                    Text("RPM")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .position(
                            x: plotRect.maxX + CurvePreviewLayout.rpmAxisLabelOffset,
                            y: plotRect.minY - 12)
                }

                curveArea(plotted: plotted, plotRect: plotRect)

                Path { path in
                    guard let first = plotted.first else { return }
                    path.move(to: first)
                    for point in plotted.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                )

                ForEach(sortedPoints) { point in
                    handle(for: point, in: proxy.size)
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

                    if draggedPointID == nil, let liveRPMText {
                        Text(liveRPMText)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.blue)
                            .contentTransition(.numericText())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.regularMaterial)
                                    .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
                            )
                            .position(liveRPMLabelPosition(for: marker, in: plotRect))
                            .allowsHitTesting(false)
                    }
                }
            }
            .animation(animatesLiveMarker ? Theme.Anim.liveMarker : nil, value: liveMarkerAnimationKey)
            .transaction { transaction in
                if !animatesLiveMarker {
                    transaction.animation = nil
                }
            }
        }
        .accessibilityLabel("curve.accessibility.preview".localized)
    }

    // MARK: - Interactive pieces

    private func handle(for point: CurvePoint, in size: CGSize) -> some View {
        let isActive = hoveredPointID == point.id || draggedPointID == point.id
        let position = position(for: point, in: size)

        return Circle()
            .fill(Theme.accent.opacity(isEditingEnabled ? 0.95 : 0.45))
            .frame(width: 14, height: 14)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.4)
            )
            .scaleEffect(isActive && isEditingEnabled ? 1.35 : 1)
            .shadow(color: .black.opacity(isEditingEnabled ? (isActive ? 0.3 : 0.2) : 0), radius: isActive ? 4 : 2, y: 1)
            .overlay(alignment: .top) {
                if isActive, isEditingEnabled {
                    valueBubble(for: point)
                        .offset(y: estimatedRPM == nil ? -30 : -40)
                        .fixedSize()
                }
            }
            .position(position)
            .onHover { hovering in
                hoveredPointID = hovering ? point.id : (hoveredPointID == point.id ? nil : hoveredPointID)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEditingEnabled else { return }
                        draggedPointID = point.id
                        updatePoint(
                            point.moved(
                                to: value.location,
                                in: size,
                                percentRange: percentRange,
                                showsRPMAxis: showsRPMAxis))
                    }
                    .onEnded { _ in
                        draggedPointID = nil
                    }
            )
            .contextMenu {
                if isEditingEnabled, let deletePoint {
                    Button(role: .destructive) {
                        deletePoint(point.id)
                    } label: {
                        Label("curve.delete_point".localized, systemImage: "trash")
                    }
                    .disabled(!canDeletePoints)
                }
            }
            .help(isEditingEnabled ? "curve.help.drag_point".localized : "curve.help.point".localized)
            .accessibilityLabel("curve.accessibility.point".localized)
            .accessibilityValue(
                "curve.accessibility.point_value".localized(
                    Int(point.temperatureCelsius.rounded()),
                    Int(point.percent.rounded())
                )
            )
    }

    private func valueBubble(for point: CurvePoint) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(point.temperatureCelsius.rounded()))°C · \(Int(point.percent.rounded()))%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let rpm = estimatedRPM?(point.percent) {
                Text(AppFormatters.approximateRPM(rpm))
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.badgeRadius, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        )
    }

    private func curveArea(plotted: [CGPoint], plotRect: CGRect) -> some View {
        Path { path in
            guard let first = plotted.first, let last = plotted.last else { return }
            path.move(to: CGPoint(x: first.x, y: plotRect.maxY))
            path.addLine(to: first)
            for point in plotted.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: plotRect.maxY))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
    }

    private func doubleClickToAdd(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard isEditingEnabled, let addPoint else { return }
                let plotRect = curvePreviewPlotRect(in: size, showsRPMAxis: showsRPMAxis)
                let clampedX = min(max(value.location.x, plotRect.minX), plotRect.maxX)
                let clampedY = min(max(value.location.y, plotRect.minY), plotRect.maxY)
                let range = CurvePoint.temperatureRange
                let temperature =
                    range.lowerBound + (clampedX - plotRect.minX) / max(1, plotRect.width)
                    * (range.upperBound - range.lowerBound)
                let rawPercent = (plotRect.maxY - clampedY) / max(1, plotRect.height) * 100
                let percent = min(max(rawPercent, percentRange.lowerBound), percentRange.upperBound)
                addPoint(temperature, percent)
            }
    }

    private var sortedPoints: [CurvePoint] {
        points.sorted { $0.temperatureCelsius < $1.temperatureCelsius }
    }

    private var axisTicks: [Double] {
        [0, 25, 50, 75, 100]
    }

    /// One RPM equivalent per percent tick for the right-hand axis, or nil
    /// when no fan can be converted (fanless Macs, missing max RPM).
    private var rpmAxisValues: [Double]? {
        guard let estimatedRPM else { return nil }
        let values = axisTicks.compactMap { estimatedRPM($0) }
        return values.count == axisTicks.count ? values : nil
    }

    private var showsRPMAxis: Bool {
        rpmAxisValues != nil
    }

    private var liveRPMText: String? {
        if let currentRPM {
            return AppFormatters.rpm(currentRPM)
        }
        guard let targetPercent, let rpm = estimatedRPM?(targetPercent) else { return nil }
        return AppFormatters.rpm(rpm)
    }

    private func liveRPMLabelPosition(for marker: CGPoint, in plotRect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(marker.x, plotRect.minX + 34), plotRect.maxX - 34),
            y: max(plotRect.minY + 9, marker.y - 18)
        )
    }

    /// Prolongs the polyline flat to both plot edges, matching how
    /// `FanCurve.percent(for:)` clamps outside the outermost points, so a
    /// three-point curve no longer looks cut off.
    private func extendedToPlotEdges(_ plotted: [CGPoint], plotRect: CGRect) -> [CGPoint] {
        guard let first = plotted.first, let last = plotted.last else { return plotted }
        var extended = plotted
        if first.x > plotRect.minX + 0.5 {
            extended.insert(CGPoint(x: plotRect.minX, y: first.y), at: 0)
        }
        if last.x < plotRect.maxX - 0.5 {
            extended.append(CGPoint(x: plotRect.maxX, y: last.y))
        }
        return extended
    }

    private var liveMarkerAnimationKey: String {
        guard let currentTemperature, let targetPercent else { return "none" }
        return String(format: "%.1f-%.1f-%.0f", currentTemperature, targetPercent, currentRPM ?? -1)
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
        curvePreviewPlotRect(in: size, showsRPMAxis: showsRPMAxis)
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

extension CurvePoint {
    fileprivate func moved(
        to location: CGPoint,
        in size: CGSize,
        percentRange: ClosedRange<Double>,
        showsRPMAxis: Bool
    ) -> CurvePoint {
        let plotRect = curvePreviewPlotRect(in: size, showsRPMAxis: showsRPMAxis)
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
    static let rpmAxisTrailingInset: CGFloat = 46
    static let rpmAxisLabelOffset: CGFloat = 24
    static let plotTopPadding: CGFloat = 22
    static let plotBottomPadding: CGFloat = 12
    static let xAxisLabelBand: CGFloat = 15
    static let xAxisLabelOffset: CGFloat = 12
}

private func curvePreviewPlotRect(in size: CGSize, showsRPMAxis: Bool) -> CGRect {
    let topInset = CurvePreviewLayout.plotTopPadding
    let bottomInset = CurvePreviewLayout.plotBottomPadding + CurvePreviewLayout.xAxisLabelBand
    let trailingInset = showsRPMAxis ? CurvePreviewLayout.rpmAxisTrailingInset : CurvePreviewLayout.trailingInset

    return CGRect(
        x: CurvePreviewLayout.leadingInset,
        y: topInset,
        width: max(1, size.width - CurvePreviewLayout.leadingInset - trailingInset),
        height: max(1, size.height - topInset - bottomInset)
    )
}
