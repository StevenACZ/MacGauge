import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager
    @ObservedObject private var helperService: HelperCommandService

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(initialValue: model.settings)
        _loginManager = ObservedObject(initialValue: model.loginManager)
        _helperService = ObservedObject(initialValue: model.helperService)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            controlTab
                .tabItem { Label("Control", systemImage: "fanblades") }

            curveTab
                .tabItem { Label("Curve", systemImage: "chart.xyaxis.line") }

            displayTab
                .tabItem { Label("Display", systemImage: "paintpalette") }

            safetyTab
                .tabItem { Label("Safety", systemImage: "exclamationmark.triangle") }
        }
        .frame(width: 600, height: 460)
        .padding(20)
    }

    private var generalTab: some View {
        Form {
            Picker("Temperature unit", selection: $settings.temperatureUnit) {
                ForEach(TemperatureUnit.allCases) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)

            Toggle(
                "Start at login",
                isOn: Binding(
                    get: { loginManager.isEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )

            HStack {
                Text("Login item")
                Spacer()
                Text(loginManager.statusText)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    loginManager.openSystemSettings()
                }
            }

            Toggle("Restore automatic fan control on quit", isOn: $settings.restoreAutomaticOnQuit)
        }
        .formStyle(.grouped)
    }

    private var controlTab: some View {
        Form {
            Picker("Default mode", selection: $settings.controlMode) {
                ForEach(FanControlMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            HStack {
                Slider(value: $settings.manualPercent, in: settings.dangerousRangesUnlocked ? 0...100 : 20...90, step: 1) {
                    Text("Manual target")
                }
                Text(AppFormatters.percent(settings.manualPercent))
                    .monospacedDigit()
                    .frame(width: 52, alignment: .trailing)
            }

            Text("Live Apply uses the bundled CLI and macOS administrator approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var curveTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach($settings.curvePoints) { $point in
                    HStack {
                        TextField("Temp", value: $point.temperatureCelsius, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 82)
                        Text("C")
                            .foregroundStyle(.secondary)
                        Slider(value: $point.percent, in: settings.dangerousRangesUnlocked ? 0...100 : 20...90, step: 1)
                        Text(AppFormatters.percent(point.percent))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .onDelete(perform: settings.removeCurvePoints)
            }

            HStack {
                Button {
                    settings.addCurvePoint()
                } label: {
                    Label("Add Point", systemImage: "plus")
                }

                Button("Reset") {
                    settings.resetCurveDefaults()
                }

                Spacer()

                Stepper(value: $settings.curveRunMinutes, in: 1...120, step: 1) {
                    Text("\(Int(settings.curveRunMinutes.rounded())) min run")
                }
            }
        }
    }

    private var displayTab: some View {
        Form {
            Toggle("Animate fan icon", isOn: $settings.animateFanIcon)

            HStack {
                TextField("Normal up to", value: $settings.normalUpperCelsius, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("C")
                Spacer()
                ColorPicker("Normal color", selection: colorBinding(\.normalColorHex))
            }

            HStack {
                TextField("Hot from", value: $settings.hotLowerCelsius, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("C")
                Spacer()
                ColorPicker("Medium color", selection: colorBinding(\.mediumColorHex))
            }

            ColorPicker("Hot color", selection: colorBinding(\.hotColorHex))

            Text("The menu bar uses normal below the first threshold, medium between thresholds, and hot above the second threshold.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var safetyTab: some View {
        Form {
            Toggle("Unlock edge ranges", isOn: $settings.dangerousRangesUnlocked)

            HStack {
                Text("Privileged helper")
                Spacer()
                Text(helperService.state.rawValue)
                    .foregroundStyle(.secondary)
                Button("Authorize") {
                    model.authorizeHelper()
                }
                .disabled(model.isWriting)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("0 RPM and near-maximum targets can damage hardware or fight macOS thermal management.")
                    .foregroundStyle(.secondary)
                Text("The helper is a narrow local LaunchDaemon. It does not store passwords.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack {
                Button {
                    model.restoreAutomatic()
                } label: {
                    Label("Restore Automatic Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.isWriting)

                Spacer()

                Text(model.lastActionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .formStyle(.grouped)
    }

    private func colorBinding(_ keyPath: ReferenceWritableKeyPath<AppSettingsStore, String>) -> Binding<Color> {
        Binding {
            Color(hexString: settings[keyPath: keyPath])
        } set: { color in
            settings[keyPath: keyPath] = NSColor.fromSwiftUIColor(color).hexString
        }
    }
}
