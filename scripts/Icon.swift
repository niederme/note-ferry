import AppKit

// Render the approved vector artwork at each native icon size. The lettering
// is outlined in the SVG, so building needs no installed design font.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
let artwork = URL(fileURLWithPath: "Resources/AppIcon.svg")
guard let image = NSImage(contentsOf: artwork) else {
    fatalError("Cannot read icon artwork at \(artwork.path)")
}
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) {
        try data.write(to: folder.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    if [32, 64, 256, 512, 1024].contains(size) {
        try data.write(to: folder.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
