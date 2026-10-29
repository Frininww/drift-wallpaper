import XCTest
import AppKit
import ImageIO
@testable import Drift

@MainActor
private final class MockBackgroundWorkspace: SystemBackgroundWorkspace {
    var displays = [BackgroundDisplay(id: "A", width: 1920, height: 1080)]
    var images = ["A": DesktopImageState(url: URL(fileURLWithPath: "/original.png"))]
    var failingDisplays: Set<String> = []
    var writes = 0
    func image(on display: String) -> DesktopImageState? { images[display] }
    func setImage(_ image: DesktopImageState, on display: String) throws {
        if failingDisplays.contains(display) { throw BackgroundError.displayUnavailable }
        images[display] = image
        writes += 1
    }
}

final class SystemBackgroundTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    func testRepeatedApplyPreservesTheOriginalRestorePointAcrossRelaunch() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = MockBackgroundWorkspace()
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        try controller.apply(["A": URL(fileURLWithPath: "/poster1.png")])
        try controller.apply(["A": URL(fileURLWithPath: "/poster2.png")])
        XCTAssertEqual(workspace.images["A"]?.url.path, "/poster2.png")
        let relaunched = try SystemBackgroundController(directory: directory, workspace: workspace)
        try relaunched.restore()
        XCTAssertEqual(workspace.images["A"]?.url.path, "/original.png")
        XCTAssertFalse(relaunched.canRestore)
    }

    @MainActor
    func testRestoreDoesNotOverwriteANewerManualWallpaper() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = MockBackgroundWorkspace()
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        try controller.apply(["A": URL(fileURLWithPath: "/poster.png")])
        workspace.images["A"] = DesktopImageState(url: URL(fileURLWithPath: "/user-choice.png"))
        try controller.restore()
        XCTAssertEqual(workspace.images["A"]?.url.path, "/user-choice.png")
        XCTAssertFalse(controller.canRestore)
    }

    @MainActor
    func testNewManualWallpaperBecomesTheNextRestorePoint() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = MockBackgroundWorkspace()
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        try controller.apply(["A": URL(fileURLWithPath: "/poster1.png")])
        workspace.images["A"] = DesktopImageState(url: URL(fileURLWithPath: "/new-original.png"))
        try controller.apply(["A": URL(fileURLWithPath: "/poster2.png")])
        try controller.restore()
        XCTAssertEqual(workspace.images["A"]?.url.path, "/new-original.png")
    }

    @MainActor
    func testPendingJournalCanRestoreAfterInterruptedApply() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pending = URL(fileURLWithPath: "/pending.png")
        let original = DesktopImageState(url: URL(fileURLWithPath: "/original.png"))
        let records = ["A": BackgroundRecord(original: original, pending: pending)]
        try JSONEncoder().encode(records).write(to: directory.appendingPathComponent("history.json"))
        let workspace = MockBackgroundWorkspace()
        workspace.images["A"] = DesktopImageState(url: pending)
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        try controller.restore()
        XCTAssertEqual(workspace.images["A"], original)
    }

    @MainActor
    func testFailedApplyReportsFailureAndLeavesOriginalUntouched() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = MockBackgroundWorkspace()
        workspace.failingDisplays = ["A"]
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        XCTAssertThrowsError(try controller.apply(["A": URL(fileURLWithPath: "/poster.png")]))
        XCTAssertEqual(workspace.images["A"]?.url.path, "/original.png")
        XCTAssertEqual(workspace.writes, 0)
    }

    @MainActor
    func testDisconnectedDisplayKeepsItsRestoreRecordUntilReconnected() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = MockBackgroundWorkspace()
        let controller = try SystemBackgroundController(directory: directory, workspace: workspace)
        try controller.apply(["A": URL(fileURLWithPath: "/poster.png")])
        let displays = workspace.displays
        workspace.displays = []
        try controller.restore()
        XCTAssertTrue(controller.canRestore)
        workspace.displays = displays
        try controller.restore()
        XCTAssertEqual(workspace.images["A"]?.url.path, "/original.png")
    }

    @MainActor
    func testUnreadableHistoryIsPreservedAndDoesNotWriteSystemState() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let data = Data("broken history".utf8)
        try data.write(to: url)
        let workspace = MockBackgroundWorkspace()
        XCTAssertThrowsError(try SystemBackgroundController(directory: directory, workspace: workspace))
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(workspace.writes, 0)
    }

    func testFitProducesLetterboxingAndFillUsesTheEntireTarget() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 4))
        let source = try XCTUnwrap(context.makeImage())
        let fit = try BackgroundImageRenderer.render(source, width: 4, height: 4, fit: .fit)
        let fill = try BackgroundImageRenderer.render(source, width: 4, height: 4, fit: .fill)
        let fitBytes = try XCTUnwrap(fit.dataProvider?.data)
        let fillBytes = try XCTUnwrap(fill.dataProvider?.data)
        XCTAssertEqual(CFDataGetBytePtr(fitBytes)[0], 0)
        XCTAssertEqual(CFDataGetBytePtr(fillBytes)[0], 255)
        XCTAssertEqual(fit.width, 4)
        XCTAssertEqual(fit.height, 4)
    }

    func testVideoFrameIsGeneratedAtSourceResolution() async throws {
        let url = try XCTUnwrap(DriftResources.bundle.url(forResource: "Aurora4K", withExtension: "mp4"))
        let frame = try await BackgroundImageRenderer.videoFrame(url, seconds: 2)
        XCTAssertEqual(frame.width, 3840)
        XCTAssertEqual(frame.height, 2160)
    }

    @MainActor
    func testStoppedRendererCannotBePreparedAgain() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No graphical display") }
        let url = try XCTUnwrap(DriftResources.bundle.url(forResource: "Aurora", withExtension: "mp4"))
        let renderer = DesktopRenderer(screen: screen, wallpaperID: UUID(), url: url, quality: .init())
        renderer.stop()
        renderer.prepare()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(renderer.stopped)
        XCTAssertFalse(renderer.window.isVisible)
        XCTAssertFalse(renderer.hasPlayer)
    }

    @MainActor
    func testStoppingPendingPreparationCannotResurrectTheWindow() async throws {
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw XCTSkip("No graphical display") }
        let url = try XCTUnwrap(DriftResources.bundle.url(forResource: "Aurora", withExtension: "mp4"))
        let renderer = DesktopRenderer(screen: screen, wallpaperID: UUID(), url: url, quality: .init())
        var callbacks = 0
        renderer.onChange = { callbacks += 1 }
        renderer.prepare()
        renderer.stop()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(renderer.window.isVisible)
        XCTAssertFalse(renderer.hasPlayer)
        XCTAssertEqual(callbacks, 0)
    }
}
