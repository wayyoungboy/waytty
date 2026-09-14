import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let frame = NSRect(x: 78, y: 78, width: 868, height: 868)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 194, yRadius: 194)
        NSGradient(starting: NSColor(calibratedWhite: 0.19, alpha: 1), ending: NSColor(calibratedWhite: 0.07, alpha: 1))!.draw(in: shape, angle: -90)
        NSColor(calibratedWhite: 0.32, alpha: 1).setStroke(); shape.lineWidth = 3; shape.stroke()
        NSColor(red: 0.25, green: 0.80, blue: 0.54, alpha: 1).setStroke()
        let prompt = NSBezierPath(); prompt.move(to: NSPoint(x: 263, y: 625)); prompt.line(to: NSPoint(x: 401, y: 508)); prompt.line(to: NSPoint(x: 263, y: 391))
        prompt.lineWidth = 52; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
        let line = NSBezierPath(); line.move(to: NSPoint(x: 490, y: 390)); line.line(to: NSPoint(x: 739, y: 390)); line.lineWidth = 49; line.lineCapStyle = .round; line.stroke()
        for x in [268, 312, 356] { NSColor(calibratedWhite: 0.4, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: x, y: 734, width: 17, height: 17)).fill() }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = bitmap.representation(using: .png, properties: [:])!
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
if process.terminationStatus != 0 { exit(process.terminationStatus) }
