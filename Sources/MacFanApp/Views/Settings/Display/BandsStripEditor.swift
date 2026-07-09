import SwiftUI

/// Interactive band strip: three colored bands with two draggable handles on
/// the thresholds, over a configurable scale (30-90 °C for temperature,
/// 0-100 % for the load charts). Text fields next to it keep precise entry
/// available.
struct BandsStripEditor: View {
    @Binding var normalUpper: Double
    @Binding var hotLower: Double

    let normalColor: Color
    let mediumColor: Color
    let hotColor: Color

    var scale: ClosedRange<Double> = 30...90
    var unitSuffix: String = "°"

    @State private var activeHandle: Handle?

    private enum Handle {
        case normal
        case hot
    }

    private let barHeight: CGFloat = 26
    private let handleSize: CGFloat = 20

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        segment(normalColor)
                            .frame(width: position(of: normalUpper, in: width))
                        segment(mediumColor)
                            .frame(width: max(0, position(of: hotLower, in: width) - position(of: normalUpper, in: width)))
                        segment(hotColor)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    handle(.normal, value: normalUpper, width: width)
                    handle(.hot, value: hotLower, width: width)
                }
                .coordinateSpace(name: "temperature-bands")
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: normalUpper)
                .animation(activeHandle == nil ? Theme.Anim.spring : nil, value: hotLower)
            }
            .frame(height: barHeight)

            HStack {
                Text("\(Int(scale.lowerBound))\(unitSuffix)")
                Spacer()
                Text("\(Int(scale.upperBound))\(unitSuffix)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .monospacedDigit()
        }
    }

    private func segment(_ color: Color) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.85), color.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func handle(_ kind: Handle, value: Double, width: CGFloat) -> some View {
        let isDragging = activeHandle == kind
        return VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: isDragging ? 3 : 1.5, y: 1)
                Text("\(Int(value.rounded()))")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.75))
            }
            .frame(width: handleSize, height: handleSize)
            .scaleEffect(isDragging ? 1.18 : 1)
            .animation(Theme.Anim.hover, value: isDragging)
        }
        .position(x: position(of: value, in: width), y: barHeight / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("temperature-bands"))
                .onChanged { drag in
                    activeHandle = kind
                    let temperature = temperature(at: drag.location.x, in: width)
                    switch kind {
                    case .normal:
                        normalUpper = temperature
                    case .hot:
                        hotLower = temperature
                    }
                }
                .onEnded { _ in
                    activeHandle = nil
                }
        )
        .accessibilityLabel(
            kind == .normal
                ? "settings.display.normal".localized
                : "settings.display.hot".localized
        )
        .accessibilityValue("\(Int(value.rounded())) \(unitSuffix)")
    }

    private func position(of temperature: Double, in width: CGFloat) -> CGFloat {
        let clamped = min(max(temperature, scale.lowerBound), scale.upperBound)
        let fraction = (clamped - scale.lowerBound) / (scale.upperBound - scale.lowerBound)
        return CGFloat(fraction) * width
    }

    private func temperature(at x: CGFloat, in width: CGFloat) -> Double {
        guard width > 0 else { return scale.lowerBound }
        let fraction = Double(min(max(x / width, 0), 1))
        return (scale.lowerBound + fraction * (scale.upperBound - scale.lowerBound)).rounded()
    }
}
