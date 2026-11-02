// Draws the app icon (sun over the horizon) and writes an .iconset folder.
// Usage: swift scripts/make_icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1),
                        NSColor(red: 0.98, green: 0.55, blue: 0.25, alpha: 1)])!.draw(in: bg, angle: -90)
    bg.addClip()
    // sun
    let r = rect.width * 0.2
    let c = NSPoint(x: rect.midX, y: rect.minY + rect.height * 0.42)
    NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)).fill()
    // rays
    NSColor(red: 1, green: 0.85, blue: 0.35, alpha: 0.9).setStroke()
    for i in 0...6 {
        let a = CGFloat.pi * CGFloat(i) / 6
        let p = NSBezierPath()
        p.lineWidth = rect.width * 0.03
        p.lineCapStyle = .round
        p.move(to: NSPoint(x: c.x + cos(a) * r * 1.35, y: c.y + sin(a) * r * 1.35))
        p.line(to: NSPoint(x: c.x + cos(a) * r * 1.75, y: c.y + sin(a) * r * 1.75))
        p.stroke()
    }
    // horizon
    NSColor(red: 0.10, green: 0.12, blue: 0.30, alpha: 1).setFill()
    NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: c.y - rect.minY).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
