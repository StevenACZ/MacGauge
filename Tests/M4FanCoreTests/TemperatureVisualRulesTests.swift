import Foundation
import Testing
@testable import M4FanCore

@Test func classifiesTemperatureBands() {
    let rules = TemperatureVisualRules(normalUpperCelsius: 45, hotLowerCelsius: 70)

    #expect(rules.band(for: 30) == .normal)
    #expect(rules.band(for: 45) == .normal)
    #expect(rules.band(for: 55) == .medium)
    #expect(rules.band(for: 70) == .hot)
}

@Test func choosesAnimationIntervalsByBand() {
    let rules = TemperatureVisualRules(normalUpperCelsius: 45, hotLowerCelsius: 70)

    #expect(rules.animationInterval(for: 35) == nil)
    #expect(rules.animationInterval(for: 55) == 0.8)
    #expect(rules.animationInterval(for: 80) == 0.25)
}

@Test func debounceWindowSchedulesAfterDelay() {
    let now = Date(timeIntervalSince1970: 100)
    let window = DebounceWindow(delay: 0.55)

    #expect(abs(window.fireDate(after: now).timeIntervalSince1970 - 100.55) < 0.001)
}
