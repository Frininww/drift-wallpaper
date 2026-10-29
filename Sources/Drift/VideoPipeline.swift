import AVFoundation
import DriftCore

@MainActor
enum VideoPipeline {
    static func makeItem(url: URL, quality: PlaybackQuality) async throws -> AVPlayerItem {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideo }
        let duration = try await asset.load(.duration)
        let transform = try await source.load(.preferredTransform)
        let naturalSize = try await source.load(.naturalSize)
        let fps = try await source.load(.nominalFrameRate)
        let bounds = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let plan = quality.plan(width: Int(abs(bounds.width)), height: Int(abs(bounds.height)), framesPerSecond: Double(fps))
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MediaError.invalid }
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)
        track.preferredTransform = transform
        try Task.checkCancellation()
        let item = AVPlayerItem(asset: composition)
        item.preferredForwardBufferDuration = 1
        if plan.needsComposition {
            track.preferredTransform = .identity
            let video = AVMutableVideoComposition()
            video.renderSize = CGSize(width: plan.width, height: plan.height)
            video.frameDuration = CMTime(seconds: 1 / plan.framesPerSecond, preferredTimescale: 60_000)
            // Preserve VFR source timing unless the user actually lowers FPS.
            video.sourceTrackIDForFrameTiming = plan.limitsFrameRate ? kCMPersistentTrackID_Invalid : track.trackID
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            let normalized = transform
                .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: Double(plan.width) / bounds.width, y: Double(plan.height) / bounds.height))
            layer.setTransform(normalized, at: .zero)
            instruction.layerInstructions = [layer]
            video.instructions = [instruction]
            item.videoComposition = video
        }
        return item
    }
}
