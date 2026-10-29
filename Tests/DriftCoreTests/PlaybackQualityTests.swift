import XCTest
@testable import DriftCore

final class PlaybackQualityTests: XCTestCase {
    func testOriginalRetains4K120WithoutComposition() {
        let plan = PlaybackQuality().plan(width: 3840, height: 2160, framesPerSecond: 120)
        XCTAssertEqual(plan.width, 3840)
        XCTAssertEqual(plan.height, 2160)
        XCTAssertEqual(plan.framesPerSecond, 120)
        XCTAssertFalse(plan.needsComposition)
    }

    func test1080p30Limits4K60() {
        var quality = PlaybackQuality()
        quality.resolution = .fullHD
        quality.frameRate = .fps30
        let plan = quality.plan(width: 3840, height: 2160, framesPerSecond: 60)
        XCTAssertEqual(plan.width, 1920)
        XCTAssertEqual(plan.height, 1080)
        XCTAssertEqual(plan.framesPerSecond, 30)
        XCTAssertTrue(plan.resizes)
        XCTAssertTrue(plan.limitsFrameRate)
    }

    func testHighLimitsNeverUpscale720p24() {
        var quality = PlaybackQuality()
        quality.resolution = .ultraHD
        quality.frameRate = .fps120
        let plan = quality.plan(width: 1280, height: 720, framesPerSecond: 24)
        XCTAssertEqual(plan.width, 1280)
        XCTAssertEqual(plan.height, 720)
        XCTAssertEqual(plan.framesPerSecond, 24)
        XCTAssertFalse(plan.needsComposition)
    }

    func testPortraitOrientationPreservesAspectRatio() {
        var quality = PlaybackQuality()
        quality.resolution = .fullHD
        let plan = quality.plan(width: 2160, height: 3840, framesPerSecond: 60)
        XCTAssertEqual(plan.width, 1080)
        XCTAssertEqual(plan.height, 1920)
    }

    func testUltrawideFitsWithinBothBoundsWithEvenDimensions() {
        var quality = PlaybackQuality()
        quality.resolution = .fullHD
        let plan = quality.plan(width: 3440, height: 1440, framesPerSecond: 60)
        XCTAssertEqual(plan.width, 1920)
        XCTAssertEqual(plan.height, 802)
        XCTAssertLessThanOrEqual(plan.height, 1080)
    }

    func testFractionalSourceCadenceIsPreservedBelowLimit() {
        var quality = PlaybackQuality()
        quality.frameRate = .fps60
        let plan = quality.plan(width: 1920, height: 1080, framesPerSecond: 59.94)
        XCTAssertEqual(plan.framesPerSecond, 59.94)
        XCTAssertFalse(plan.needsComposition)
    }

    func test1440pAnd4KCapsAllowMoreDetail() {
        var quality = PlaybackQuality()
        quality.resolution = .quadHD
        let qhd = quality.plan(width: 7680, height: 4320, framesPerSecond: 120)
        XCTAssertEqual(qhd.width, 2560)
        XCTAssertEqual(qhd.height, 1440)
        quality.resolution = .ultraHD
        let uhd = quality.plan(width: 7680, height: 4320, framesPerSecond: 120)
        XCTAssertEqual(uhd.width, 3840)
        XCTAssertEqual(uhd.height, 2160)
        XCTAssertEqual(uhd.framesPerSecond, 120)
    }

    func testInvalidMetadataCannotProduceNaNOrZeroDimensions() {
        var quality = PlaybackQuality()
        quality.resolution = .fullHD
        let plan = quality.plan(width: 0, height: 0, framesPerSecond: .nan)
        XCTAssertGreaterThan(plan.width, 0)
        XCTAssertGreaterThan(plan.height, 0)
        XCTAssertTrue(plan.framesPerSecond.isFinite)
    }
}
