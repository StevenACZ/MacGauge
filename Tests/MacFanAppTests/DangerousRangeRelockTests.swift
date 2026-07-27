import XCTest

@testable import MacFanApp

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

    func testRelockingRangesIsRefusedWhileAWriteIsInFlight() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.dangerousRangesUnlocked = true
        model.settings.manualPercent = 0
        model.isWriting = true

        model.setDangerousRangesUnlocked(false)

        XCTAssertTrue(model.settings.dangerousRangesUnlocked)
        XCTAssertEqual(model.settings.manualPercent, 0)
    }

    func testRelockingRangesGoesThroughOnceTheWriteFinished() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.dangerousRangesUnlocked = true
        model.settings.manualPercent = 0

        model.setDangerousRangesUnlocked(false)

        XCTAssertFalse(model.settings.dangerousRangesUnlocked)
        XCTAssertEqual(model.settings.manualPercent, 20)
    }

    func testUnlockingRangesNeverMovesTheManualTarget() {
        let model = AppModel()
        model.settings.controlMode = .manual
        model.settings.manualPercent = 45

        model.settings.dangerousRangesUnlocked = true

        XCTAssertEqual(model.settings.manualPercent, 45)
    }
}
