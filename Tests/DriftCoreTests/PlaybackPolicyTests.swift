import XCTest
@testable import DriftCore

final class PlaybackPolicyTests: XCTestCase {
    func testVisibleDesktopPlaysByDefault() {
        XCTAssertNil(PlaybackPolicy.pauseReason(environment: .init(), settings: .init()))
    }

    func testEverySafetyConditionPausesAndRecovers() {
        let conditions: [(WritableKeyPath<PlaybackEnvironment, Bool>, Bool, PauseReason)] = [
            (\.manuallyPaused, true, .manual), (\.sleeping, true, .sleeping),
            (\.sessionActive, false, .inactiveSession), (\.thermallyConstrained, true, .thermal),
            (\.lowPowerMode, true, .lowPower), (\.desktopVisible, false, .covered)
        ]
        for (path, value, reason) in conditions {
            var environment = PlaybackEnvironment()
            let original = environment[keyPath: path]
            environment[keyPath: path] = value
            XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: .init()), reason)
            environment[keyPath: path] = original
            XCTAssertNil(PlaybackPolicy.pauseReason(environment: environment, settings: .init()))
        }
    }

    func testUserPauseSurvivesWakeAndVisibilityChanges() {
        var environment = PlaybackEnvironment()
        environment.manuallyPaused = true
        environment.sleeping = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: .init()), .manual)
        environment.sleeping = false
        environment.desktopVisible = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: .init()), .manual)
    }

    func testBatteryPauseIsOptIn() {
        var environment = PlaybackEnvironment()
        environment.onBattery = true
        XCTAssertNil(PlaybackPolicy.pauseReason(environment: environment, settings: .init()))
        var settings = EnergySettings()
        settings.pauseOnBattery = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: settings), .battery)
    }

    func testOptionalPoliciesCanBeDisabledWithoutDisablingThermalProtection() {
        var settings = EnergySettings()
        settings.pauseWhenCovered = false
        settings.pauseInLowPowerMode = false
        var environment = PlaybackEnvironment()
        environment.lowPowerMode = true
        environment.desktopVisible = false
        XCTAssertNil(PlaybackPolicy.pauseReason(environment: environment, settings: settings))
        environment.thermallyConstrained = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: settings), .thermal)
    }

    func testDisplaysMakeIndependentOcclusionDecisions() {
        var hidden = PlaybackEnvironment()
        hidden.desktopVisible = false
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: hidden, settings: .init()), .covered)
        XCTAssertNil(PlaybackPolicy.pauseReason(environment: .init(), settings: .init()))
    }

    func testHigherPriorityReasonDoesNotHideManualPause() {
        var environment = PlaybackEnvironment()
        environment.manuallyPaused = true
        environment.thermallyConstrained = true
        environment.lowPowerMode = true
        environment.onBattery = true
        environment.desktopVisible = false
        var settings = EnergySettings()
        settings.pauseOnBattery = true
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: settings), .manual)
        environment.manuallyPaused = false
        XCTAssertEqual(PlaybackPolicy.pauseReason(environment: environment, settings: settings), .thermal)
    }
}
