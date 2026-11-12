// Renders Glide's app icon into an .iconset folder. Usage: swift make_icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSGradient(colors: [NSColor(red: 0.29, green: 0.42, blue: 1.0, alpha: 1),
                        NSColor(red: 0.55, green: 0.27, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -50)
    NSGraphicsContext.current?.restoreGraphicsState()

    // Motion streaks behind the mouse = "glide".
    NSColor.white.withAlphaComponent(0.35).setStroke()
    for (i, y) in [0.40, 0.50, 0.60].enumerated() {
        let line = NSBezierPath()
        line.lineWidth = s * 0.028
        line.lineCapStyle = .round
        let x0 = s * (0.22 + 0.03 * Double(i % 2))
        line.move(to: NSPoint(x: x0, y: s * y))
        line.line(to: NSPoint(x: s * 0.40, y: s * y))
        line.stroke()
    }

    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let sz = sym.size
        sym.draw(in: NSRect(x: s * 0.56 - sz.width / 2, y: s * 0.5 - sz.height / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: out.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: out.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print("icon rendered")
