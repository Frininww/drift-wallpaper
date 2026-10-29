import Foundation

public enum PauseReason: String, Sendable, Codable, CaseIterable {
    case manual, sleeping, inactiveSession, thermal, lowPower, battery, covered
}

public struct PlaybackEnvironment: Sendable {
    public var manuallyPaused = false
    public var sleeping = false
    public var sessionActive = true
    public var thermallyConstrained = false
    public var lowPowerMode = false
    public var onBattery = false
    public var desktopVisible = true
    public init() {}
}

public struct EnergySettings: Codable, Equatable, Sendable {
    public var pauseWhenCovered = true
    public var pauseInLowPowerMode = true
    public var pauseOnBattery = false
    public init() {}
}

/// A single decision shared by every display. Ordering makes the UI explain the
/// most actionable reason when several power conditions are active at once.
public enum PlaybackPolicy {
    public static func pauseReason(environment e: PlaybackEnvironment, settings s: EnergySettings) -> PauseReason? {
        if e.manuallyPaused { return .manual }
        if e.sleeping { return .sleeping }
        if !e.sessionActive { return .inactiveSession }
        if e.thermallyConstrained { return .thermal }
        if s.pauseInLowPowerMode && e.lowPowerMode { return .lowPower }
        if s.pauseOnBattery && e.onBattery { return .battery }
        if s.pauseWhenCovered && !e.desktopVisible { return .covered }
        return nil
    }
}
