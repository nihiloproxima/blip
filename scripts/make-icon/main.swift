import AppKit

// Génère AppIcon.iconset à partir du sprite de Pet.swift : `make-icon <dossier>`.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let pixels = Pet.coloredPixels(mood: .happy, level: 1, alert: false)
let minX = pixels.map(\.x).min()!, maxX = pixels.map(\.x).max()!
let minY = pixels.map(\.y).min()!, maxY = pixels.map(\.y).max()!

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = CGFloat(points * scale)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        // Fond arrondi aux proportions des icônes macOS.
        let inset = side * 0.1
        let background = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset), xRadius: side * 0.18, yRadius: side * 0.18)
        NSGradient(starting: NSColor(rgb: 0x3B2D63), ending: NSColor(rgb: 0x16122A))!.draw(in: background, angle: -90)

        // Sprite centré, pixels nets.
        NSGraphicsContext.current?.shouldAntialias = false
        let pixel = side * 0.56 / CGFloat(Pet.size)
        let originX = (side - CGFloat(maxX - minX + 1) * pixel) / 2
        let originY = (side - CGFloat(maxY - minY + 1) * pixel) / 2
        for dot in pixels {
            NSColor(rgb: dot.rgb).setFill()
            NSRect(x: originX + CGFloat(dot.x - minX) * pixel, y: side - originY - CGFloat(dot.y - minY + 1) * pixel, width: pixel, height: pixel).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appending(path: name))
    }
}
