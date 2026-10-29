import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case english = "en", russian = "ru"
    public var name: String { self == .english ? "English" : "Русский" }
}

public enum ResolutionLimit: Int, Codable, CaseIterable, Sendable {
    case original = 0, fullHD = 1080, quadHD = 1440, ultraHD = 2160
    public var name: String { self == .original ? "Original" : "\(rawValue)p" }
}

public enum FrameRateLimit: Int, Codable, CaseIterable, Sendable {
    case original = 0, fps24 = 24, fps30 = 30, fps60 = 60, fps120 = 120
}

public struct PlaybackQuality: Codable, Equatable, Sendable {
    public var resolution = ResolutionLimit.original
    public var frameRate = FrameRateLimit.original
    public init() {}

    /// Limits preserve aspect ratio, never upscale, and never invent frames.
    /// The default preserves source timing and avoids a video compositor.
    public func plan(width: Int, height: Int, framesPerSecond: Double) -> RenderPlan {
        let sourceWidth = max(2, width), sourceHeight = max(2, height)
        var scale = 1.0
        if resolution != .original {
            let shortLimit = Double(resolution.rawValue)
            scale = min(1, shortLimit / Double(min(sourceWidth, sourceHeight)),
                        shortLimit * 16 / 9 / Double(max(sourceWidth, sourceHeight)))
        }
        let resized = scale < 0.99999
        let outputWidth = resized ? max(2, Int(Double(sourceWidth) * scale / 2) * 2) : sourceWidth
        let outputHeight = resized ? max(2, Int(Double(sourceHeight) * scale / 2) * 2) : sourceHeight
        let sourceFPS = framesPerSecond.isFinite && framesPerSecond > 0 ? framesPerSecond : 30
        let outputFPS = frameRate == .original ? sourceFPS : min(sourceFPS, Double(frameRate.rawValue))
        return RenderPlan(width: outputWidth, height: outputHeight, framesPerSecond: outputFPS,
                          resizes: resized, limitsFrameRate: outputFPS < sourceFPS - 0.001)
    }
}

public struct RenderPlan: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let framesPerSecond: Double
    public let resizes: Bool
    public let limitsFrameRate: Bool
    public var needsComposition: Bool { resizes || limitsFrameRate }
}
