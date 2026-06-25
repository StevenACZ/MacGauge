import SwiftUI

struct SafetySettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var helperService: HelperCommandService

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "lock.shield", title: "Safety") {
                SettingsRow(title: "Unlock edge ranges") {
                    Toggle("", isOn: $settings.dangerousRangesUnlocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "Privileged helper") {
                    HStack(spacing: 12) {
                        HelperStatusBadge(state: helperService.state)
                        if !helperService.isReady {
                            Button {
                                model.authorizeHelper()
                            } label: {
                                Label(authorizeButtonTitle, systemImage: authorizeButtonIcon)
                            }
                            .disabled(model.isWriting)
                        }
                    }
                }

                SettingsDivider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("0 RPM and near-maximum targets can damage hardware or fight macOS thermal management.")
                    Text("The helper is a narrow SMAppService LaunchDaemon with an XPC Mach service. It does not store passwords.")
                    Text("macOS may require one explicit approval from this Safety action before controls are unlocked.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                SettingsDivider()

                HStack {
                    Button {
                        model.restoreAutomatic()
                    } label: {
                        Label("Restore Automatic Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!helperService.isReady || model.isWriting)

                    Spacer()

                    Text(model.lastActionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .onAppear {
            model.refreshHelperState()
        }
    }

    private var authorizeButtonTitle: String {
        helperService.state == .needsApproval ? "Open Settings" : "Authorize"
    }

    private var authorizeButtonIcon: String {
        helperService.state == .needsApproval ? "arrow.up.forward.app" : "lock.open"
    }
}
