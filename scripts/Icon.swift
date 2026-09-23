import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for stale in ["icon_64x64.png", "icon_64x64@2x.png"] { try? FileManager.default.removeItem(at: folder.appendingPathComponent(stale)) }
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.53, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210).fill()
    NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 245, y: 200, width: 534, height: 650), xRadius: 42, yRadius: 42).fill()
    NSColor(calibratedRed: 0.38, green: 0.40, blue: 0.64, alpha: 1).setFill()
    for (y, width) in [(710, 328), (610, 250), (510, 328), (410, 205)] {
        NSBezierPath(roundedRect: NSRect(x: 320, y: y, width: width, height: 32), xRadius: 16, yRadius: 16).fill()
    }
    NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 590, y: 145, width: 270, height: 270)).fill()
    let check = NSBezierPath(); check.move(to: NSPoint(x: 653, y: 280)); check.line(to: NSPoint(x: 704, y: 228)); check.line(to: NSPoint(x: 792, y: 326)); check.lineWidth = 28; check.lineCapStyle = .round; check.lineJoinStyle = .round
    NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.53, alpha: 1).setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) { try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size).png")) }
    if [32, 64, 256, 512, 1024].contains(size) { try data.write(to: folder.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png")) }
}
