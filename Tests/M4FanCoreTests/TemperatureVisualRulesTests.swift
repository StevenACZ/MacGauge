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

@Test func debounceWindowSchedulesAfterDelay() {
    let now = Date(timeIntervalSince1970: 100)
    let window = DebounceWindow(delay: 0.55)

    #expect(abs(window.fireDate(after: now).timeIntervalSince1970 - 100.55) < 0.001)
}

@Test func visualRulesKeepHotThresholdAboveNormalThreshold() {
    let rules = TemperatureVisualRules(normalUpperCelsius: 70, hotLowerCelsius: 45)

    #expect(rules.normalUpperCelsius == 70)
    #expect(rules.hotLowerCelsius == 71)
    #expect(rules.band(for: 70) == .normal)
    #expect(rules.band(for: 70.5) == .medium)
    #expect(rules.band(for: 71) == .hot)
}

@Test func debounceWindowClampsNegativeDelayToZero() {
    let now = Date(timeIntervalSince1970: 100)
    let window = DebounceWindow(delay: -1)

    #expect(window.fireDate(after: now) == now)
}
