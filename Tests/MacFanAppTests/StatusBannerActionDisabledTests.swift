import XCTest

@testable import MacFanApp

/// `actionDisabled` gates the Authorize/Fix button so an in-flight repair
/// cannot be fired twice. It must stay defaulted: the contested and fanless
/// banners are action-less and never pass it.
final class StatusBannerActionDisabledTests: XCTestCase {

    func testActionlessBannerDefaultsToEnabled() {
        let banner = StatusBanner(
            severity: .warning,
            icon: "exclamationmark.triangle.fill",
            message: "contested"
        )

        XCTAssertFalse(banner.actionDisabled)
        XCTAssertNil(banner.action)
    }

    func testBannerCarriesTheBusyGateToItsAction() {
        let banner = StatusBanner(
            severity: .info,
            icon: "lock.shield",
            message: "authorize",
            actionTitle: "Authorize",
            actionDisabled: true,
            action: {}
        )

        XCTAssertTrue(banner.actionDisabled)
        XCTAssertNotNil(banner.action)
    }
}
