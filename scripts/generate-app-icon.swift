#!/usr/bin/env swift
import AppKit

// Unico A1.1 — the “Merge Notch” production source.
// Four aligned source layers: full-bleed background, rear glass, front glass,
// and the U-shaped merge bridge. The system can add its own icon treatment;
// this script keeps the identity in broad, clean source geometry.

let canvas = CGFloat(1024)
let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ??
    "/Users/leowy/未与/04_素材/封面/Unico/icon-director-A1.1")

struct Palette {
    let background: NSColor
    let rearTop: NSColor
    let rearBottom: NSColor
    let frontTop: NSColor
    let frontBottom: NSColor
    let bridge: NSColor
    let rim: NSColor
}

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        red: CGFloat((value >> 16) & 0xff) / 255,
        green: CGFloat((value >> 8) & 0xff) / 255,
        blue: CGFloat(value & 0xff) / 255,
        alpha: alpha
    )
}

let variants: [(String, Palette)] = [
    ("default", Palette(
        background: hex(0x101B33), rearTop: hex(0x4F6D9B, 0.86), rearBottom: hex(0x263B61, 0.92),
        frontTop: hex(0xFFF8EA, 0.84), frontBottom: hex(0xD7E4F7, 0.72),
        bridge: hex(0x70B4FF, 0.94), rim: hex(0xFFFFFF, 0.64)
    )),
    ("dark", Palette(
        background: hex(0x080E1B), rearTop: hex(0x314666, 0.92), rearBottom: hex(0x192842, 0.95),
        frontTop: hex(0xDCE8F7, 0.76), frontBottom: hex(0x8EA9CC, 0.62),
        bridge: hex(0x74B7FF, 0.96), rim: hex(0xEAF3FF, 0.54)
    )),
    ("mono", Palette(
        background: hex(0x1A1A1C), rearTop: hex(0x72757B, 0.92), rearBottom: hex(0x383A3E, 0.96),
        frontTop: hex(0xF3F3F3, 0.82), frontBottom: hex(0xBBBBBD, 0.74),
        bridge: hex(0x161719, 0.94), rim: hex(0xFFFFFF, 0.58)
    ))
]

let rearRect = NSRect(x: 404, y: 158, width: 466, height: 466)
let frontRect = NSRect(x: 150, y: 358, width: 466, height: 466)

func cardPath(_ rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: 88, yRadius: 88)
}

func fillGradient(_ shape: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
    NSGradient(starting: bottom, ending: top)!.draw(in: shape, angle: 90)
}

func strokeRim(_ shape: NSBezierPath, _ color: NSColor, _ width: CGFloat = 4) {
    color.setStroke()
    shape.lineWidth = width
    shape.stroke()
}

func drawRear(_ palette: Palette, material: Bool) {
    let shape = cardPath(rearRect)
    if material {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 28
        shadow.shadowOffset = NSSize(width: 8, height: -12)
        shadow.set()
    }
    fillGradient(shape, palette.rearTop, palette.rearBottom)
    if material { strokeRim(shape, palette.rim.withAlphaComponent(0.44), 4) }
}

func drawFront(_ palette: Palette, material: Bool) {
    let shape = cardPath(frontRect)
    if material {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 26
        shadow.shadowOffset = NSSize(width: 4, height: -12)
        shadow.set()
    }
    fillGradient(shape, palette.frontTop, palette.frontBottom)
    if material { strokeRim(shape, palette.rim, 5) }
}

func drawBridge(_ palette: Palette, material: Bool) {
    let bridge = NSBezierPath()
    bridge.move(to: NSPoint(x: 352, y: 610))
    bridge.line(to: NSPoint(x: 352, y: 485))
    bridge.curve(to: NSPoint(x: 506, y: 344), controlPoint1: NSPoint(x: 352, y: 394), controlPoint2: NSPoint(x: 421, y: 344))
    bridge.curve(to: NSPoint(x: 660, y: 485), controlPoint1: NSPoint(x: 591, y: 344), controlPoint2: NSPoint(x: 660, y: 394))
    bridge.line(to: NSPoint(x: 660, y: 610))
    bridge.lineWidth = 92
    bridge.lineCapStyle = .round
    bridge.lineJoinStyle = .round
    if material {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = NSSize(width: 0, height: -5)
        shadow.set()
    }
    palette.bridge.setStroke()
    bridge.stroke()
    if material {
        palette.rim.withAlphaComponent(0.34).setStroke()
        bridge.lineWidth = 5
        bridge.stroke()
    }
}

func bitmap(_ draw: @escaping () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, _ url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

for (name, palette) in variants {
    let folder = output.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try write(bitmap { palette.background.setFill(); NSRect(x: 0, y: 0, width: canvas, height: canvas).fill() }, folder.appendingPathComponent("01-background.png"))
    try write(bitmap { drawRear(palette, material: false) }, folder.appendingPathComponent("02-rear-glass.png"))
    try write(bitmap { drawFront(palette, material: false) }, folder.appendingPathComponent("03-front-glass.png"))
    try write(bitmap { drawBridge(palette, material: false) }, folder.appendingPathComponent("04-merge-bridge.png"))
    try write(bitmap {
        palette.background.setFill(); NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()
        drawRear(palette, material: true)
        drawFront(palette, material: true)
        drawBridge(palette, material: true)
    }, folder.appendingPathComponent("Unico-A1.1-\(name).png"))
}

print("Generated Unico A1.1 source layers at \(output.path)")
