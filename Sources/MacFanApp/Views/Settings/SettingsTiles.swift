import SwiftUI

struct OptionTile<Preview: View>: View {
    let title: String
    var caption: String?
    let isSelected: Bool
    var previewHeight: CGFloat = 38
    var mocksMenuBar = true
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                previewPlate

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                        .padding(.top, 1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let caption {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(stroke, lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.Anim.hover) {
                isHovered = hovering
            }
        }
        .animation(Theme.Anim.spring, value: isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var previewPlate: some View {
        let plate = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if mocksMenuBar {
            preview()
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .background(plate.fill(Color.black.opacity(0.82)))
        } else {
            preview()
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .background(plate.fill(Color.primary.opacity(0.05)))
        }
    }

    private var fill: Color {
        if isSelected { return Theme.accent.opacity(0.1) }
        return Color.primary.opacity(isHovered ? 0.07 : 0.035)
    }

    private var stroke: Color {
        if isSelected { return Theme.accent.opacity(0.9) }
        return Color.primary.opacity(isHovered ? 0.18 : 0.09)
    }
}

struct OptionTilePicker<Value: Hashable & Identifiable, Preview: View>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: KeyPath<Value, String>
    var previewHeight: CGFloat = 38
    @ViewBuilder let preview: (Value) -> Preview

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(options) { option in
                OptionTile(
                    title: option[keyPath: label],
                    isSelected: option == selection,
                    previewHeight: previewHeight,
                    action: { selection = option }
                ) {
                    preview(option)
                }
            }
        }
    }
}

struct SettingsGroupHeader: View {
    let title: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.semibold))
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum PreviewSamples {
    static let load: [Double] = [18, 26, 22, 34, 30, 46, 40, 55, 44, 63, 52, 71, 60, 78]
}

struct SampleSparkline: View {
    let style: AnyShapeStyle
    var width: CGFloat = 40
    var values: [Double] = PreviewSamples.load

    var body: some View {
        let vector = AnimatableValues(values: Array(values.reversed()))
        ZStack {
            SparklineShape(vector: vector, peak: 100, capacity: values.count, closesToBaseline: true)
                .fill(style)
                .opacity(0.3)
            SparklineShape(vector: vector, peak: 100, capacity: values.count, closesToBaseline: false)
                .stroke(style, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }
        .frame(width: width, height: 15)
        .background(AppearancePalette.menuBarChartPlate)
        .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
    }
}

struct SamplePercentModule: View {
    let title: String
    let style: AnyShapeStyle
    var graphWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 3) {
            VStack(spacing: -1) {
                Text(title)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(style)
                    .shadow(color: AppearancePalette.menuBarHalo, radius: 1)
                Text(verbatim: "64%")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
            }
            SampleSparkline(style: style, width: graphWidth)
        }
        .fixedSize()
    }
}
