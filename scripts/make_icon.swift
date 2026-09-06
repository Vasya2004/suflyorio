import AppKit

let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                              bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.30, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
for (index, width) in [560.0, 440.0, 560.0, 310.0].enumerated() {
    NSBezierPath(roundedRect: NSRect(x: 200, y: 700 - Double(index) * 125, width: width, height: 48), xRadius: 24, yRadius: 24).fill()
}
NSColor(calibratedRed: 1, green: 0.39, blue: 0.32, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 655, y: 190, width: 170, height: 170)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
