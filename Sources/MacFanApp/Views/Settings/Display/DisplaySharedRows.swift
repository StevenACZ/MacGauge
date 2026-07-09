import SwiftUI

/// Rows and helpers shared by the Display-tab section cards.

struct StylePickerRow<Value: Hashable & Identifiable>: View {
    let title: String
    let caption: String
    let options: [Value]
    let label: KeyPath<Value, String>
    @Binding var selection: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

// These rows sit next to the 156pt sidebar, so their rigid widths must
// stay under SettingsLayout.contentWidth − sidebar − card padding or the
// whole settings window loses its margins (the tab ZStack adopts the
// widest tab's minimum width).
struct VisualThresholdRow: View {
    let title: String
    let thresholdLabel: String
    @Binding var value: Double
    @Binding var colorHex: String
    var unit: String = "°C"

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 72, alignment: .leading)

            Text(thresholdLabel)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            TextField(title, value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
            Text(unit)
                .foregroundStyle(.secondary)

            Spacer()

            ColorPresetPicker(selection: $colorHex)
        }
        .padding(.vertical, 2)
    }
}

struct VisualBandRow: View {
    let title: String
    let rangeText: String
    @Binding var colorHex: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 72, alignment: .leading)

            Text(rangeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(Theme.Anim.smooth, value: rangeText)

            Spacer()

            ColorPresetPicker(selection: $colorHex)
        }
        .padding(.vertical, 2)
    }
}

/// Centered note shown when the previewed module is hidden in the menu bar.
struct HiddenModuleHint: View {
    let isShown: Bool

    var body: some View {
        if !isShown {
            Label("settings.display.module.hidden_hint".localized, systemImage: "eye.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Dark capsule mock of the menu bar around simulated module content,
/// with the simulated-data note underneath. Forcing the dark scheme keeps
/// label-colored styles readable in light mode.
struct SimulatedPreviewCapsule<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Spacer(minLength: 0)
                content()
                    .menuBarMockCapsule(verticalPadding: 4)
                    .environment(\.colorScheme, .dark)
                Spacer(minLength: 0)
            }

            Text("settings.display.preview.simulated".localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

/// Dark rounded rectangle that mocks the menu bar behind preview content.
/// The fan preview keeps its 5pt of vertical padding, the module previews 4pt.
private struct MenuBarMockCapsule: ViewModifier {
    let verticalPadding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.82))
            )
    }
}

extension View {
    func menuBarMockCapsule(verticalPadding: CGFloat) -> some View {
        modifier(MenuBarMockCapsule(verticalPadding: verticalPadding))
    }
}

extension AppSettingsStore {
    func colorHexBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<String> {
        Binding {
            self[keyPath: keyPath]
        } set: { hex in
            self[keyPath: keyPath] = hex
        }
    }

    /// Clamped, ordered bindings for a normal-ceiling / hot-floor threshold
    /// pair: the normal ceiling can never climb into the hot floor and vice
    /// versa, so a visible middle band always survives.
    func orderedThresholdBindings(
        normalUpper: ReferenceWritableKeyPath<AppSettingsStore, Double>,
        hotLower: ReferenceWritableKeyPath<AppSettingsStore, Double>,
        floor: Double,
        ceiling: Double,
        gap: Double
    ) -> (normalUpper: Binding<Double>, hotLower: Binding<Double>) {
        (
            normalUpper: Binding {
                self[keyPath: normalUpper]
            } set: { value in
                guard value.isFinite else { return }
                self[keyPath: normalUpper] = min(max(value.rounded(), floor), self[keyPath: hotLower] - gap)
            },
            hotLower: Binding {
                self[keyPath: hotLower]
            } set: { value in
                guard value.isFinite else { return }
                self[keyPath: hotLower] = max(min(value.rounded(), ceiling), self[keyPath: normalUpper] + gap)
            }
        )
    }
}
