import AppKit
import SwiftUI

struct LoginItemsGuide: View {
    enum Section {
        case backgroundActivity
        case openAtLogin
    }

    var section: Section = .backgroundActivity
    let isWaiting: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0

    private static let phaseCount = 5
    private static let phaseNanoseconds: UInt64 = 900_000_000

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.6)
            VStack(alignment: .leading, spacing: 8) {
                Text(sectionTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Group {
                    switch section {
                    case .backgroundActivity:
                        backgroundActivityList
                    case .openAtLogin:
                        openAtLoginList
                    }
                }
                .cardChrome(radius: 8, fill: Color.primary.opacity(0.04), stroke: Color.primary.opacity(0.08))
            }
            .padding(12)
        }
        .cardChrome(radius: 12, fill: Color(nsColor: .windowBackgroundColor), stroke: Color.primary.opacity(0.14))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .task(id: animates) { await loop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var sectionTitle: String {
        switch section {
        case .backgroundActivity: SystemSettingsLabels.backgroundActivity
        case .openAtLogin: SystemSettingsLabels.openAtLogin
        }
    }

    private var accessibilityText: String {
        switch section {
        case .backgroundActivity: "guide.accessibility".localized(sectionTitle)
        case .openAtLogin: "guide.login_accessibility".localized(sectionTitle)
        }
    }

    // MARK: - Lists

    private var backgroundActivityList: some View {
        VStack(spacing: 0) {
            placeholderRow(nameWidth: 64) { GuideSwitch(isOn: true).opacity(0.45) }
            Divider().padding(.leading, 38)
            macGaugeRow(highlighted: isWaiting) {
                GuideSwitch(isOn: switchOn)
                    .overlay(alignment: .topLeading) { cursor }
            }
            Divider().padding(.leading, 38)
            placeholderRow(nameWidth: 88) { GuideSwitch(isOn: false).opacity(0.45) }
        }
    }

    private var openAtLoginList: some View {
        VStack(spacing: 0) {
            placeholderRow(nameWidth: 70) { kindPlaceholder }
            Divider().padding(.leading, 38)
            placeholderRow(nameWidth: 52) { kindPlaceholder }
            if !isWaiting {
                Divider().padding(.leading, 38)
                macGaugeRow(highlighted: true) {
                    if let application = SystemSettingsLabels.application {
                        Text(application)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    } else {
                        kindPlaceholder
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "plus")
                Image(systemName: "minus")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        }
        .animation(.easeInOut(duration: 0.35), value: isWaiting)
    }

    // MARK: - Pieces

    private var titleBar: some View {
        HStack(spacing: 6) {
            ForEach(Self.trafficLights, id: \.self) { color in
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.leading, 8)
            Text(SystemSettingsLabels.loginItems)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if section == .backgroundActivity {
                passwordBadge
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private static let trafficLights = [
        Color(red: 1, green: 0.37, blue: 0.34),
        Color(red: 1, green: 0.74, blue: 0.18),
        Color(red: 0.16, green: 0.79, blue: 0.25),
    ]

    private func macGaugeRow<Trailing: View>(highlighted: Bool, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 22, height: 22)
            Text(verbatim: "MacGauge")
                .font(.system(size: 11.5, weight: .medium))
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlAccentColor).opacity(highlighted ? 0.10 : 0))
        )
    }

    private func placeholderRow<Trailing: View>(nameWidth: CGFloat, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 22, height: 22)
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: nameWidth, height: 7)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var kindPlaceholder: some View {
        Capsule()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 44, height: 6)
    }

    private var cursor: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color.black)
            .shadow(color: .white, radius: 0.6)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .scaleEffect(displayedPhase == 2 ? 0.82 : 1, anchor: .topLeading)
            .offset(x: displayedPhase >= 1 ? 12 : 70, y: displayedPhase >= 1 ? 7 : 44)
            .opacity(isWaiting && (1...3).contains(displayedPhase) ? 1 : 0)
            .allowsHitTesting(false)
    }

    private var passwordBadge: some View {
        Label("guide.password".localized, systemImage: "touchid")
            .font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .opacity(isWaiting && displayedPhase >= 3 ? 1 : 0)
            .offset(x: isWaiting && displayedPhase >= 3 ? 0 : 6)
    }

    // MARK: - Timeline

    private var animates: Bool {
        section == .backgroundActivity && isWaiting && !reduceMotion
    }

    private var switchOn: Bool {
        !isWaiting || displayedPhase >= 2
    }

    private var displayedPhase: Int {
        reduceMotion ? 3 : phase
    }

    private func loop() async {
        phase = 0
        guard animates else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.phaseNanoseconds)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                phase = (phase + 1) % Self.phaseCount
            }
        }
    }
}

private struct GuideSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color(nsColor: .controlAccentColor) : Color.primary.opacity(0.18))
            .frame(width: 28, height: 16)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(1.5)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }
    }
}
