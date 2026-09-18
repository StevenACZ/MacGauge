import SwiftUI

struct WelcomeView: View {
    let openSetup: () -> Void
    let startMonitoring: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text("welcome.title".localized)
                        .font(.system(size: 24, weight: .bold))
                    Text("welcome.subtitle".localized)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("welcome.monitoring.title".localized, systemImage: "chart.xyaxis.line")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text("welcome.monitoring.body".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 10) {
                Text("welcome.optional.title".localized)
                    .font(.headline)
                Text("welcome.optional.body".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("welcome.optional.action".localized, action: openSetup)
                    .buttonStyle(.bordered)
            }
            Button(action: startMonitoring) {
                Text("welcome.start".localized)
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .tint(Theme.accent)
    }
}
