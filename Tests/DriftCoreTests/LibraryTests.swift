import XCTest
@testable import DriftCore

final class LibraryTests: XCTestCase {
    private func wallpaper(filename: String = "clip.mp4") -> Wallpaper {
        Wallpaper(name: "Coast", filename: filename, width: 1920, height: 1080,
                  duration: 12, framesPerSecond: 24, byteCount: 5_000_000)
    }

    func testStorageRoundTripPreservesSettingsAndSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        var state = LibraryState()
        let video = wallpaper()
        state.wallpapers = [video]
        state.settings.selectedID = video.id
        state.settings.disabledDisplays = ["42"]
        state.settings.manuallyPaused = true
        state.settings.energy.pauseOnBattery = true
        try LibraryStorage.save(state, to: file)
        XCTAssertEqual(try LibraryStorage.load(from: file), state)
        state.settings.fit = .fit
        try LibraryStorage.save(state, to: file)
        XCTAssertEqual(try LibraryStorage.load(from: file), state)
    }

    func testDeletingSelectedWallpaperClearsSelection() {
        var state = LibraryState()
        let video = wallpaper()
        state.wallpapers = [video]
        state.settings.selectedID = video.id
        state.remove(video.id)
        XCTAssertTrue(state.wallpapers.isEmpty)
        XCTAssertNil(state.settings.selectedID)
    }

    func testDeletingAnotherWallpaperPreservesSelection() {
        var state = LibraryState()
        let first = wallpaper(), second = wallpaper()
        state.wallpapers = [first, second]
        state.settings.selectedID = first.id
        state.remove(second.id)
        XCTAssertEqual(state.settings.selectedID, first.id)
        XCTAssertEqual(state.wallpapers, [first])
    }

    func testManifestCannotEscapeLibraryDirectory() {
        let state = LibraryState()
        let directory = URL(fileURLWithPath: "/tmp/drift-library")
        for filename in ["../other.mp4", "/etc/passwd", "folder/video.mp4", "", ".", ".."] {
            XCTAssertNil(state.mediaURL(for: wallpaper(filename: filename), in: directory), filename)
        }
        XCTAssertEqual(state.mediaURL(for: wallpaper(), in: directory)?.path, "/tmp/drift-library/clip.mp4")
    }

    func testUnsupportedManifestVersionIsRejected() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        var state = LibraryState()
        state.version = 2
        try LibraryStorage.save(state, to: file)
        XCTAssertThrowsError(try LibraryStorage.load(from: file))
    }

    func testInvalidJSONDoesNotProduceAnEmptyLibrary() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("not json".utf8).write(to: file)
        XCTAssertThrowsError(try LibraryStorage.load(from: file))
    }

    func testHighResolutionAndHighFrameRateAreFlagged() {
        var video = wallpaper()
        XCTAssertFalse(video.needsOptimization)
        video.width = 3840
        XCTAssertTrue(video.needsOptimization)
        video.width = 1920
        video.framesPerSecond = 60
        XCTAssertTrue(video.needsOptimization)
    }
}
