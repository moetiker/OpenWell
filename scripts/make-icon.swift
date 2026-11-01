// Draws the app icon and writes OpenWell.icns: make icon
import AppKit

func render(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size) / 1024

    // the macOS icon grid: an 824 point rounded square in a 1024 point canvas
    let body = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * s, yRadius: 185 * s)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    // black body, yellow window with a plus, a yellow and black hazard stripe at
    // the bottom
    let yellow = NSColor(srgbRed: 1.00, green: 0.82, blue: 0.05, alpha: 1)
    NSGradient(colors: [
        NSColor(srgbRed: 0.16, green: 0.16, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.04, green: 0.04, blue: 0.04, alpha: 1),
    ])!.draw(in: path, angle: -90)

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let band = NSRect(x: body.minX, y: body.minY, width: body.width, height: 150 * s)
    yellow.setFill()
    band.fill()
    NSColor.black.setFill()
    let stripe = 70 * s
    var x = body.minX - band.height
    while x < body.maxX {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: band.minY))
        p.line(to: NSPoint(x: x + stripe, y: band.minY))
        p.line(to: NSPoint(x: x + stripe + band.height, y: band.maxY))
        p.line(to: NSPoint(x: x + band.height, y: band.maxY))
        p.close()
        p.fill()
        x += 2 * stripe
    }
    // a soft highlight on the upper half, the glass look of macOS 26 icons
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: 400 * s, weight: .semibold)
        .applying(.init(paletteColors: [yellow]))
    if let symbol = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let glow = NSShadow()
        glow.shadowColor = yellow.withAlphaComponent(0.45)
        glow.shadowBlurRadius = 40 * s
        NSGraphicsContext.saveGraphicsState()
        glow.set()
        let r = NSRect(x: body.midX - symbol.size.width / 2, y: body.midY + 60 * s - symbol.size.height / 2,
            width: symbol.size.width, height: symbol.size.height)
        symbol.draw(in: r)
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : NSTemporaryDirectory() + "OpenWell.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try render(size: points * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", "OpenWell.icns", iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(iconutil.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}
print("Wrote OpenWell.icns")
