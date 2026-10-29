import AppKit
import AVFoundation
import DriftCore

enum MediaError: LocalizedError {
    case invalid, noVideo, tooShort
    var errorDescription: String? {
        switch self {
        case .invalid: return "Не удалось прочитать видео. Выбери локальный MP4, MOV или M4V с кодеком H.264 или HEVC."
        case .noVideo: return "В этом файле нет видеодорожки."
        case .tooShort: return "Видео должно иметь конечную длительность не меньше одной секунды."
        }
    }
}

enum MediaImporter {
    /// AVFoundation loads track metadata asynchronously; copying runs away from
    /// the main actor. The source is retained until the import has completed.
    static func inspectAndCopy(_ source: URL, into directory: URL) async throws -> Wallpaper {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: source)
        guard try await asset.load(.isPlayable) else { throw MediaError.invalid }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideo }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 1 else { throw MediaError.tooShort }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let dimensions = size.applying(transform)
        let fps = try await track.load(.nominalFrameRate)
        let id = UUID()
        let ext = source.pathExtension.lowercased()
        let filename = "\(id.uuidString).\(["mp4", "mov", "m4v"].contains(ext) ? ext : "mov")"
        let destination = directory.appendingPathComponent(filename)
        try Task.checkCancellation()
        try FileManager.default.copyItem(at: source, to: destination)
        let bytes = (try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Wallpaper(id: id, name: source.deletingPathExtension().lastPathComponent, filename: filename,
                         width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)), duration: duration,
                         framesPerSecond: Double(fps), byteCount: Int64(bytes))
    }

    static func thumbnail(_ url: URL) async -> NSImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 450)
        do {
            let result = try await generator.image(at: .zero)
            return NSImage(cgImage: result.image, size: .zero)
        } catch { return nil }
    }
}
