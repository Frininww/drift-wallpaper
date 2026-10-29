// Generates the original, seamless eight-second demo bundled with Drift.
// swiftc scripts/GenerateDemo.swift -o /tmp/drift-demo && /tmp/drift-demo output.mp4
import AppKit
import AVFoundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: destination)
let width = 1280, height = 720, fps = 24, frames = 192
let writer = try AVAssetWriter(outputURL: destination, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_800_000, AVVideoExpectedSourceFrameRateKey: fps,
                                     AVVideoMaxKeyFrameIntervalKey: fps * 2]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
])
writer.add(input)
guard writer.startWriting() else { fatalError(writer.error!.localizedDescription) }
writer.startSession(atSourceTime: .zero)
let space = CGColorSpaceCreateDeviceRGB()
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    autoreleasepool {
        var optional: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &optional)
        let buffer = optional!
        CVPixelBufferLockBaseAddress(buffer, [])
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        let t = Double(frame) / Double(frames) * .pi * 2
        let background = CGGradient(colorsSpace: space, colors: [color(0.025, 0.055, 0.13), color(0.12, 0.19, 0.30), color(0.24, 0.34, 0.37)] as CFArray, locations: [0, 0.65, 1])!
        context.drawLinearGradient(background, start: CGPoint(x: 0, y: 720), end: .zero, options: [])
        // Soft ribbons curve through a full period, so the last frame flows into the first.
        for ribbon in (0..<14).reversed() {
            let j = Double(ribbon)
            let lift = sin(t + j * 0.11) * 35
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -160, y: 320 + j * 11 + lift))
            path.addCurve(to: CGPoint(x: 1440, y: 575 + j * 5 - lift),
                          control1: CGPoint(x: 370, y: 740 + j * 12 + lift),
                          control2: CGPoint(x: 740, y: 180 + j * 13 - lift))
            path.addLine(to: CGPoint(x: 1440, y: 670 + j * 7 - lift))
            path.addCurve(to: CGPoint(x: -160, y: 400 + j * 10 + lift),
                          control1: CGPoint(x: 780, y: 330 + j * 12 - lift),
                          control2: CGPoint(x: 340, y: 860 + j * 9 + lift))
            path.closeSubpath()
            context.saveGState()
            context.addPath(path); context.clip()
            let glow = CGGradient(colorsSpace: space, colors: [color(0.39, 0.89, 0.74, 0.055), color(0.43, 0.44, 0.77, 0.13), color(0.65, 0.64, 0.85, 0.045)] as CFArray, locations: [0, 0.60, 1])!
            context.drawLinearGradient(glow, start: CGPoint(x: 0, y: 500), end: CGPoint(x: 1280, y: 480), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        }
        // Deterministic stars and distant silhouettes.
        for star in 0..<68 {
            let x = Double((star * 197 + 51) % 1280)
            let y = Double((star * 83 + 383) % 340 + 350)
            context.setFillColor(color(0.86, 0.92, 0.94, 0.22 + Double(star % 3) * 0.08))
            context.fillEllipse(in: CGRect(x: x, y: y, width: star % 7 == 0 ? 2 : 1, height: star % 7 == 0 ? 2 : 1))
        }
        for layer in 0..<3 {
            let path = CGMutablePath()
            path.move(to: .zero)
            for x in stride(from: 0, through: 1280, by: 16) {
                let y = 110.0 - Double(layer) * 33 + sin(Double(x) * 0.005 + Double(layer) * 2) * 45 + cos(Double(x) * 0.013 + Double(layer)) * 12
                path.addLine(to: CGPoint(x: Double(x), y: y))
            }
            path.addLine(to: CGPoint(x: 1280, y: 0)); path.closeSubpath()
            context.addPath(path)
            context.setFillColor(color(0.035 - Double(layer) * 0.008, 0.075 - Double(layer) * 0.02, 0.12 - Double(layer) * 0.025))
            context.fillPath()
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else {
            fatalError(writer.error?.localizedDescription ?? "Encoding failed")
        }
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError(writer.error!.localizedDescription) }
print("Created \(destination.lastPathComponent): 1280×720, 24 fps, 8 seconds")
