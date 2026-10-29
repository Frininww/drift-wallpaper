import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("Drift-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let rect = CGRect(x: 85, y: 85, width: 854, height: 854)
        let shape = CGPath(roundedRect: rect, cornerWidth: 190, cornerHeight: 190, transform: nil)
        context.addPath(shape); context.clip()
        let colors = [NSColor(calibratedRed: 0.10, green: 0.20, blue: 0.27, alpha: 1).cgColor,
                      NSColor(calibratedRed: 0.025, green: 0.06, blue: 0.13, alpha: 1).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 150, y: 900), end: CGPoint(x: 850, y: 100), options: [])
        context.setStrokeColor(NSColor(calibratedRed: 0.76, green: 0.92, blue: 0.60, alpha: 1).cgColor)
        context.setLineWidth(44); context.setLineCap(.round)
        for index in 0..<3 {
            let offset = CGFloat(index) * 125
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 265, y: 350 + offset))
            path.addCurve(to: CGPoint(x: 770, y: 420 + offset), control1: CGPoint(x: 425, y: 590 + offset), control2: CGPoint(x: 590, y: 180 + offset))
            context.addPath(path); context.strokePath()
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
