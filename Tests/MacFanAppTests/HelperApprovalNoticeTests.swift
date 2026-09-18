import XCTest

@testable import MacFanApp

final class HelperApprovalNoticeTests: XCTestCase {

    func testVisibleWhileApprovalIsPending() {
        XCTAssertTrue(HelperApprovalNotice.isVisible(state: .needsApproval, fanControlAvailable: true))
    }

    func testHiddenOnceTheHelperIsEnabled() {
        XCTAssertFalse(HelperApprovalNotice.isVisible(state: .ready, fanControlAvailable: true))
    }

    func testHiddenWithoutFanControl() {
        XCTAssertFalse(HelperApprovalNotice.isVisible(state: .needsApproval, fanControlAvailable: false))
    }

    func testBannerStaysAwayOnceTheHelperIsReady() {
        XCTAssertFalse(HelperApprovalNotice.showsBanner(state: .ready, fanControlAvailable: true))
    }

    func testBannerHidesTheApprovalStateWithoutFanControl() {
        XCTAssertFalse(HelperApprovalNotice.showsBanner(state: .needsApproval, fanControlAvailable: false))
        XCTAssertTrue(HelperApprovalNotice.showsBanner(state: .needsApproval, fanControlAvailable: true))
    }

    func testBannerStillCoversTheOtherDegradedStates() {
        XCTAssertTrue(HelperApprovalNotice.showsBanner(state: .failed, fanControlAvailable: true))
        XCTAssertTrue(HelperApprovalNotice.showsBanner(state: .needsAuthorization, fanControlAvailable: true))
    }

    func testOtherHelperStatesDoNotRaiseTheApprovalNotice() {
        for state: HelperCommandService.HelperState in [.unknown, .needsAuthorization, .unavailable, .stale, .reloading, .failed] {
            XCTAssertFalse(
                HelperApprovalNotice.isVisible(state: state, fanControlAvailable: true),
                state.rawValue
            )
        }
    }
}
