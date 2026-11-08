import AppKit

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let c = NSGraphicsContext.current!.cgContext
    c.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let scale = CGFloat(size) / 1024
    c.translateBy(x: 0, y: CGFloat(size))
    c.scaleBy(x: scale, y: -scale)
    c.translateBy(x: 512, y: 512)
    c.scaleBy(x: 1.08, y: 1.08)
    c.translateBy(x: -512, y: -512)
    c.setStrokeColor(NSColor(srgbRed: 63/255, green: 82/255, blue: 104/255, alpha: 1).cgColor)
    c.setFillColor(NSColor(srgbRed: 0.985, green: 0.992, blue: 1, alpha: 1).cgColor)
    c.setLineWidth(22)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: 512, y: 322))
    c.addCurve(to: CGPoint(x: 196, y: 276), control1: CGPoint(x: 420, y: 265), control2: CGPoint(x: 302, y: 245))
    c.addLine(to: CGPoint(x: 196, y: 744))
    c.addCurve(to: CGPoint(x: 512, y: 793), control1: CGPoint(x: 301, y: 715), control2: CGPoint(x: 413, y: 734))
    c.addCurve(to: CGPoint(x: 828, y: 744), control1: CGPoint(x: 611, y: 734), control2: CGPoint(x: 723, y: 715))
    c.addLine(to: CGPoint(x: 828, y: 276))
    c.addCurve(to: CGPoint(x: 512, y: 322), control1: CGPoint(x: 722, y: 245), control2: CGPoint(x: 604, y: 265))
    c.closePath()
    // The pages are opaque, but there is no surrounding tile or background fill.
    c.drawPath(using: .fillStroke)
    c.setLineWidth(18)
    c.move(to: CGPoint(x: 512, y: 322)); c.addLine(to: CGPoint(x: 512, y: 793))
    c.strokePath()
    c.setStrokeColor(NSColor(srgbRed: 116/255, green: 140/255, blue: 165/255, alpha: 1).cgColor)
    c.setLineWidth(23)
    for y in [386, 491] {
        c.move(to: CGPoint(x: 278, y: y))
        c.addCurve(to: CGPoint(x: 425, y: y + 27), control1: CGPoint(x: 329, y: y - 4), control2: CGPoint(x: 377, y: y + 6))
    }
    c.move(to: CGPoint(x: 607, y: 413))
    c.addCurve(to: CGPoint(x: 754, y: 386), control1: CGPoint(x: 655, y: 392), control2: CGPoint(x: 703, y: 382))
    c.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(base)x\(base)" + (scale == 2 ? "@2x" : "") + ".png"
        try render(size: base * scale).write(to: folder.appendingPathComponent(name))
    }
}
