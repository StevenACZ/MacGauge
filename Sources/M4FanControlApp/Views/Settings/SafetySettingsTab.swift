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

                HStack {
                    Button {
                        model.restoreAutomatic()
                    } label: {
                        Label("Restore Automatic Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!helperService.isReady || model.isWriting)

                    Spacer()
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
