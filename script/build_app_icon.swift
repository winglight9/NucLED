import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("usage: build_app_icon.swift <traced-skull.png> <output.png>")
}

let sourcePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
guard let skull = NSImage(contentsOfFile: sourcePath) else {
    fatalError("Couldn't read traced skull image at \(sourcePath)")
}

let side = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Couldn't allocate app icon canvas")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let canvas = CGRect(x: 0, y: 0, width: side, height: side)
NSColor.clear.setFill()
canvas.fill()

let background = NSBezierPath(roundedRect: canvas, xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.23, alpha: 1),
    NSColor(calibratedRed: 0.025, green: 0.04, blue: 0.07, alpha: 1)
])?.draw(in: background, angle: 315)

let ratio = skull.size.width / skull.size.height
let skullHeight: CGFloat = 850
let skullWidth = skullHeight * ratio
let skullRect = CGRect(
    x: (CGFloat(side) - skullWidth) / 2,
    y: (CGFloat(side) - skullHeight) / 2,
    width: skullWidth,
    height: skullHeight
)
skull.draw(in: skullRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])

NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Couldn't encode app icon")
}
try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
