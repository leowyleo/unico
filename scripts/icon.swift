import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
// Keep the packaging source aligned with the approved App Store artwork.
// This is the 1024 px, opaque master included in the icon package.
let source = packageRoot.appendingPathComponent("Resources/AppIcon/Unico-AppStore-1024.png")
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Unico.iconset")

guard FileManager.default.fileExists(atPath: source.path) else {
    fatalError("Missing approved App Store icon source: \(source.path).")
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 2 ? "@2x" : ""
        let target = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        process.arguments = ["-z", "\(pixels)", "\(pixels)", source.path, "--out", target.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            fatalError("sips failed while creating \(target.lastPathComponent).")
        }
    }
}
