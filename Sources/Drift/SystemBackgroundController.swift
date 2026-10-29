import AppKit
import AVFoundation
import CryptoKit
import DriftCore
import ImageIO
import UniformTypeIdentifiers

struct BackgroundDisplay: Equatable, Sendable {
    let id: String
    let width: Int
    let height: Int
}

struct DesktopImageState: Codable, Equatable {
    var url: URL
    var scaling: Int = Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue)
    var clips = true
    var fill: [Double] = [0, 0, 0, 1]
}

struct BackgroundRecord: Codable, Equatable {
    var original: DesktopImageState?
    var applied: URL?
    var pending: URL?

    func owns(_ url: URL?) -> Bool {
        guard let url else { return false }
        return [applied, pending].compactMap { $0 }.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }
}

@MainActor
protocol SystemBackgroundWorkspace {
    var displays: [BackgroundDisplay] { get }
    func image(on display: String) -> DesktopImageState?
    func setImage(_ image: DesktopImageState, on display: String) throws
}

@MainActor
struct MacBackgroundWorkspace: SystemBackgroundWorkspace {
    var displays: [BackgroundDisplay] {
        NSScreen.screens.map {
            BackgroundDisplay(id: $0.driftID, width: Int($0.frame.width * $0.backingScaleFactor), height: Int($0.frame.height * $0.backingScaleFactor))
        }
    }

    func image(on display: String) -> DesktopImageState? {
        guard let screen = NSScreen.screens.first(where: { $0.driftID == display }),
              let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let color = ((options[.fillColor] as? NSColor) ?? .black).usingColorSpace(.deviceRGB)
            ?? NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        return DesktopImageState(url: url, scaling: (options[.imageScaling] as? NSNumber)?.intValue ?? Int(NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                                 clips: (options[.allowClipping] as? Bool) ?? true,
                                 fill: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent])
    }

    func setImage(_ image: DesktopImageState, on display: String) throws {
        guard let screen = NSScreen.screens.first(where: { $0.driftID == display }) else { throw BackgroundError.displayUnavailable }
        let fill = image.fill.count == 4 ? image.fill : [0, 0, 0, 1]
        try NSWorkspace.shared.setDesktopImageURL(image.url, for: screen, options: [
            .imageScaling: image.scaling, .allowClipping: image.clips,
            .fillColor: NSColor(red: fill[0], green: fill[1], blue: fill[2], alpha: fill[3])
        ])
    }
}

enum BackgroundError: LocalizedError {
    case displayUnavailable, invalidImage, noDisplays, failed([String])
    var errorDescription: String? {
        switch self {
        case .displayUnavailable: return "The display is no longer connected."
        case .invalidImage: return "The image could not be decoded or saved."
        case .noDisplays: return "No displays are connected."
        case .failed(let messages): return messages.joined(separator: "\n")
        }
    }
}

/// Manages system still images only. NSWorkspace does not expose an independent
/// animated Lock Screen API. It applies to current desktop spaces; macOS owns
/// how these images appear on its secure Lock Screen.
@MainActor
final class SystemBackgroundController {
    private let workspace: any SystemBackgroundWorkspace
    private let manifest: URL
    private(set) var records: [String: BackgroundRecord]
    let directory: URL
    var displays: [BackgroundDisplay] { workspace.displays }
    var canRestore: Bool { !records.isEmpty }

    init(directory: URL, workspace: any SystemBackgroundWorkspace = MacBackgroundWorkspace()) throws {
        self.directory = directory
        self.workspace = workspace
        manifest = directory.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: manifest.path) {
            // Never overwrite unreadable restoration data or mutate the system
            // until the user can recover that history.
            records = try JSONDecoder().decode([String: BackgroundRecord].self, from: Data(contentsOf: manifest))
        } else { records = [:] }
    }

    @discardableResult
    func apply(_ images: [String: URL]) throws -> Int {
        let displays = workspace.displays
        guard !displays.isEmpty else { throw BackgroundError.noDisplays }
        guard displays.contains(where: { images[$0.id] != nil }) else { throw BackgroundError.displayUnavailable }
        var failures: [String] = []
        var applied = 0
        for display in displays {
            guard let url = images[display.id] else { continue }
            let current = workspace.image(on: display.id)
            // A manual change made outside Drift becomes the new restore point.
            if let record = records[display.id], let current, !record.owns(current.url) {
                records[display.id] = BackgroundRecord(original: current)
            } else if records[display.id] == nil {
                records[display.id] = BackgroundRecord(original: current)
            }
            records[display.id]?.pending = url
            do {
                try save() // Durable intent, before changing system state.
                try workspace.setImage(DesktopImageState(url: url), on: display.id)
                applied += 1
                records[display.id]?.applied = url
                records[display.id]?.pending = nil
                try save()
            } catch { failures.append("\(display.id): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { throw BackgroundError.failed(failures) }
        return applied
    }

    func restore() throws {
        var failures: [String] = []
        for display in workspace.displays {
            guard let record = records[display.id] else { continue }
            guard let current = workspace.image(on: display.id) else {
                failures.append("\(display.id): The current system image could not be read.")
                continue
            }
            if !record.owns(current.url) {
                // Leave a newer user-selected wallpaper alone.
                records[display.id] = nil
                continue
            }
            guard let original = record.original else {
                failures.append("\(display.id): No previous system image was available.")
                continue
            }
            do {
                try workspace.setImage(original, on: display.id)
                records[display.id] = nil
            } catch { failures.append("\(display.id): \(error.localizedDescription)") }
        }
        try save()
        if !failures.isEmpty { throw BackgroundError.failed(failures) }
    }

    private func save() throws {
        try JSONEncoder().encode(records).write(to: manifest, options: .atomic)
    }
}

enum BackgroundImageRenderer {
    static func videoFrame(_ url: URL, seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.maximumSize = CGSize(width: 7680, height: 7680)
        return try await generator.image(at: CMTime(seconds: max(0, seconds), preferredTimescale: 600)).image
    }

    static func photo(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 7680
              ] as CFDictionary) else { throw BackgroundError.invalidImage }
        return image
    }

    static func write(_ image: CGImage, for displays: [BackgroundDisplay], fit: VideoFit, key: String, in directory: URL) throws -> [String: URL] {
        var images: [String: URL] = [:]
        for display in displays {
            try Task.checkCancellation()
            let hash = SHA256.hash(data: Data("\(key)|\(display.width)x\(display.height)|\(fit.rawValue)".utf8))
                .map { String(format: "%02x", $0) }.joined()
            let url = directory.appendingPathComponent("\(hash).png")
            if !FileManager.default.fileExists(atPath: url.path) {
                let frame = try render(image, width: display.width, height: display.height, fit: fit)
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw BackgroundError.invalidImage }
                CGImageDestinationAddImage(destination, frame, nil)
                guard CGImageDestinationFinalize(destination) else { throw BackgroundError.invalidImage }
                try (data as Data).write(to: url, options: .atomic)
            }
            images[display.id] = url
        }
        return images
    }

    static func render(_ image: CGImage, width: Int, height: Int, fit: VideoFit) throws -> CGImage {
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw BackgroundError.invalidImage }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let x = Double(width) / Double(image.width), y = Double(height) / Double(image.height)
        let scale = fit == .fill ? max(x, y) : min(x, y)
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (Double(width) - w) / 2, y: (Double(height) - h) / 2, width: w, height: h))
        guard let output = context.makeImage() else { throw BackgroundError.invalidImage }
        return output
    }
}
