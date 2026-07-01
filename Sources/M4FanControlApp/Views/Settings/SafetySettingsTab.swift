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
                        Text(helperService.statusSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
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
        switch helperService.state {
        case .needsApproval:
            return "Open Settings"
        case .stale, .unavailable, .failed:
            return "Reload Helper"
        case .unknown, .needsAuthorization, .ready:
            return "Authorize"
        }
    }

    private var authorizeButtonIcon: String {
        switch helperService.state {
        case .needsApproval:
            return "arrow.up.forward.app"
        case .stale, .unavailable, .failed:
            return "arrow.clockwise"
        case .unknown, .needsAuthorization, .ready:
            return "lock.open"
        }
    }
}
