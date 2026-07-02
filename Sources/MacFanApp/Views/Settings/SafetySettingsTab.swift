import SwiftUI

struct SafetySettingsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettingsStore
    @ObservedObject var helperService: HelperCommandService

    var body: some View {
        SettingsPane {
            SettingsSurface(icon: "lock.shield", title: "settings.safety.title".localized) {
                SettingsRow(title: "settings.safety.unlock_ranges".localized) {
                    Toggle("", isOn: $settings.dangerousRangesUnlocked)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                SettingsDivider()

                SettingsRow(title: "settings.safety.privileged_helper".localized) {
                    HStack(spacing: 12) {
                        if helperService.isRecovering {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            HelperStatusBadge(state: helperService.state)
                        }
                        Text(helperService.statusSummary)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if !helperService.isReady && !helperService.isRecovering {
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
                        Label("settings.safety.restore_automatic".localized, systemImage: "arrow.triangle.2.circlepath")
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
            return "settings.safety.open_settings".localized
        case .stale, .unavailable, .failed:
            return "settings.safety.fix_helper".localized
        case .unknown, .needsAuthorization, .ready, .reloading:
            return "settings.safety.authorize".localized
        }
    }

    private var authorizeButtonIcon: String {
        switch helperService.state {
        case .needsApproval:
            return "arrow.up.forward.app"
        case .stale, .unavailable, .failed:
            return "arrow.clockwise"
        case .unknown, .needsAuthorization, .ready, .reloading:
            return "lock.open"
        }
    }
}
