import XCTest
import AVFoundation
import DriftCore
@testable import Drift

final class VideoPipelineTests: XCTestCase {
    @MainActor
    func testOriginalDemoHasReal4K60AndNoPlaybackAudio() async throws {
        let url = try XCTUnwrap(DriftResources.bundle.url(forResource: "Aurora4K", withExtension: "mp4"))
        let item = try await VideoPipeline.makeItem(url: url, quality: .init())
        XCTAssertNil(item.videoComposition)
        let tracks = try await item.asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        let audio = try await item.asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(size, CGSize(width: 3840, height: 2160))
        XCTAssertEqual(fps, 60, accuracy: 0.01)
        XCTAssertTrue(audio.isEmpty)
    }

    @MainActor
    func testCompositionProduces1080pAt30FPS() async throws {
        let url = try XCTUnwrap(DriftResources.bundle.url(forResource: "Aurora4K", withExtension: "mp4"))
        var quality = PlaybackQuality()
        quality.resolution = .fullHD
        quality.frameRate = .fps30
        let item = try await VideoPipeline.makeItem(url: url, quality: quality)
        let composition = try XCTUnwrap(item.videoComposition)
        XCTAssertEqual(composition.renderSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(composition.frameDuration.seconds, 1 / 30, accuracy: 0.00001)
        let generator = AVAssetImageGenerator(asset: item.asset)
        generator.videoComposition = composition
        let frame = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600))
        XCTAssertEqual(frame.image.width, 1920)
        XCTAssertEqual(frame.image.height, 1080)
    }

    func testEnglishAndRussianHaveMatchingLocalizationKeys() throws {
        func strings(_ language: String) throws -> [String: String] {
            let folder = try XCTUnwrap(DriftResources.bundle.url(forResource: language, withExtension: "lproj"))
            let data = try Data(contentsOf: folder.appendingPathComponent("Localizable.strings"))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: String])
        }
        let english = try strings("en"), russian = try strings("ru")
        XCTAssertFalse(english.isEmpty)
        XCTAssertEqual(Set(english.keys), Set(russian.keys))
        XCTAssertEqual(Localizer(language: .english).text("nav.wallpapers"), "Wallpapers")
        XCTAssertEqual(Localizer(language: .russian).text("nav.wallpapers"), "Обои")
    }
}
