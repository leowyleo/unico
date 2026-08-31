import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Unico.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r, green: g, blue: b, alpha: 1) }
func gradient(_ path: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: path, angle: 90)
}
func shadowed(_ blur: CGFloat, _ offset: NSSize, _ opacity: CGFloat, draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
    shadow.shadowBlurRadius = blur; shadow.shadowOffset = offset; shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}
func edge(_ path: NSBezierPath, white: CGFloat, width: CGFloat) {
    NSColor.white.withAlphaComponent(white).setStroke(); path.lineWidth = width; path.stroke()
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 512); transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 27, y: 31, width: 458, height: 458), xRadius: 104, yRadius: 104)
        shadowed(12, NSSize(width: 0, height: -6), 0.18) {
            gradient(tile, rgb(0.995, 0.985, 0.957), rgb(0.87, 0.84, 0.79))
        }
        edge(tile, white: 0.7, width: 2)

        NSGraphicsContext.saveGraphicsState()
        let tilt = NSAffineTransform()
        tilt.translateX(by: 218, yBy: 274); tilt.rotate(byDegrees: 6); tilt.translateX(by: -218, yBy: -274); tilt.concat()
        let rearEdge = NSBezierPath(roundedRect: NSRect(x: 116, y: 148, width: 202, height: 246), xRadius: 34, yRadius: 34)
        shadowed(13, NSSize(width: 1, height: -8), 0.20) { rgb(0.65, 0.49, 0.38).setFill(); rearEdge.fill() }
        let rear = NSBezierPath(roundedRect: NSRect(x: 116, y: 155, width: 202, height: 246), xRadius: 34, yRadius: 34)
        gradient(rear, rgb(0.98, 0.91, 0.83), rgb(0.79, 0.64, 0.53))
        edge(rear, white: 0.55, width: 1.5)
        NSGraphicsContext.restoreGraphicsState()

        let lip = NSBezierPath(roundedRect: NSRect(x: 190, y: 104, width: 202, height: 246), xRadius: 34, yRadius: 34)
        shadowed(15, NSSize(width: 4, height: -10), 0.28) { rgb(0.43, 0.19, 0.12).setFill(); lip.fill() }
        let front = NSBezierPath(roundedRect: NSRect(x: 188, y: 114, width: 202, height: 246), xRadius: 34, yRadius: 34)
        gradient(front, rgb(0.79, 0.43, 0.29), rgb(0.56, 0.23, 0.15))
        edge(front, white: 0.24, width: 1.5)
        // A short upper rim catches the same soft light as the back plate.
        let rim = NSBezierPath(); rim.move(to: NSPoint(x: 222, y: 357)); rim.line(to: NSPoint(x: 353, y: 357))
        rim.lineWidth = 2; rim.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.27).setStroke(); rim.stroke()

        let check = NSBezierPath(); check.move(to: NSPoint(x: 240, y: 238)); check.line(to: NSPoint(x: 274, y: 204)); check.line(to: NSPoint(x: 337, y: 268))
        check.lineWidth = 17; check.lineCapStyle = .round; check.lineJoinStyle = .round
        shadowed(2, NSSize(width: 0, height: -2), 0.23) { rgb(0.995, 0.975, 0.935).setStroke(); check.stroke() }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
