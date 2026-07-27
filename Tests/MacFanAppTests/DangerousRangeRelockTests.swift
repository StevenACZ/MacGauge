import XCTest

@testable import MacFanApp

/// Turning "Unlock extreme ranges" back off has to pull a manual target that
/// sits outside the safe band back inside it. Manual mode has no periodic
/// re-apply, so an out-of-band target would otherwise survive the re-lock and
/// keep the fan below the guard rail.
@MainActor
final class DangerousRangeRelockTests: XCTestCase {

    private static let touchedDefaultsKeys = ["controlMode", "manualPercent", "dangerousRangesUnlocked"]

    override func setUp() {
        super.setUp()
        clearTouchedDefaults()
    }

    override func tearDown() {
        clearTouchedDefaults()
        super.tearDown()
    }

    private func clearTouchedDefaults() {
        for key in Self.touchedDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testRelockingRangesPullsAnOutOfBandManualTargetBackToTheFloor() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.dangerousRangesUnlocked = true
        model.settings.manualPercent = 0

        model.settings.dangerousRangesUnlocked = false

        XCTAssertEqual(model.settings.manualPercent, 20)
        XCTAssertTrue(model.manualPercentRange.contains(model.settings.manualPercent))
    }

    func testRelockingRangesClampsAnOutOfBandCeilingToo() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.dangerousRangesUnlocked = true
        model.settings.manualPercent = 100

        model.settings.dangerousRangesUnlocked = false

        XCTAssertEqual(model.settings.manualPercent, 90)
    }

    func testRelockingRangesLeavesAnInBandManualTargetUntouched() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.dangerousRangesUnlocked = true
        model.settings.manualPercent = 55

        model.settings.dangerousRangesUnlocked = false

        XCTAssertEqual(model.settings.manualPercent, 55)
    }

    func testUnlockingRangesNeverMovesTheManualTarget() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.manualPercent = 45

        model.settings.dangerousRangesUnlocked = true

        XCTAssertEqual(model.settings.manualPercent, 45)
    }
}
