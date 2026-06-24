import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var loginManager: LaunchAtLoginManager

    init(model: AppModel) {
        self.model = model
        _settings = ObservedObject(initialValue: model.settings)
        _loginManager = ObservedObject(initialValue: model.loginManager)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }

            controlTab
                .tabItem { Label("Control", systemImage: "fanblades") }

            curveTab
                .tabItem { Label("Curve", systemImage: "chart.xyaxis.line") }

            safetyTab
                .tabItem { Label("Safety", systemImage: "exclamationmark.triangle") }
        }
        .frame(width: 560, height: 420)
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

    private var safetyTab: some View {
        Form {
            Toggle("Unlock edge ranges", isOn: $settings.dangerousRangesUnlocked)

            VStack(alignment: .leading, spacing: 6) {
                Text("0 RPM and near-maximum targets can damage hardware or fight macOS thermal management.")
                    .foregroundStyle(.secondary)
                Text("Persistent root control requires a signed privileged helper; this app currently delegates live writes to the bundled CLI.")
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
}
