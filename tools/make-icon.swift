// Draws the app icon and writes AppIcon.icns next to build.sh.   swiftc tools/make-icon.swift -o /tmp/make-icon && /tmp/make-icon
// (Not part of the app: build.sh only compiles the *.swift files in the project root.)

import Cocoa

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

func render() -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // The macOS icon grid: an 824 pt squircle centered on the 1024 pt canvas.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0.2, 0.12, 0.45))
    ctx.fillPath()
    ctx.restoreGState()

    // Everything else is clipped to the body.
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // Same blue → purple → pink as the settings preview.
    ctx.drawLinearGradient(
        gradient([(0, color(0.16, 0.36, 0.95)), (0.5, color(0.30, 0.13, 0.52)), (1, color(0.70, 0.24, 0.52))]),
        start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // A faint sheen on the upper half.
    ctx.drawLinearGradient(
        gradient([(0, color(1, 1, 1, 0.16)), (1, color(1, 1, 1, 0))]),
        start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])

    // The "screen": a dashed rounded rectangle, like the menu bar icon.
    let screen = CGRect(x: 232, y: 322, width: 560, height: 380)
    ctx.saveGState()
    ctx.setStrokeColor(color(1, 1, 1, 0.92))
    ctx.setLineWidth(28)
    ctx.setLineCap(.round)
    // 18 dashes that close evenly around the rounded rectangle (round caps add the line width to each dash).
    let radius: CGFloat = 80
    let perimeter = 2 * (screen.width - 2 * radius) + 2 * (screen.height - 2 * radius) + 2 * .pi * radius
    let period = perimeter / 18
    ctx.setLineDash(phase: 0, lengths: [period * 0.47, period * 0.53])
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.strokePath()
    ctx.restoreGState()

    // The corner that just fired: a warm glow with a white-hot middle.
    let hot = CGPoint(x: screen.minX, y: screen.maxY)
    ctx.drawRadialGradient(
        gradient([
            (0, color(1, 1, 1, 1)), (0.18, color(1.0, 0.93, 0.62, 0.95)), (0.45, color(1.0, 0.62, 0.30, 0.50)), (1, color(1.0, 0.45, 0.25, 0)),
        ]),
        startCenter: hot, startRadius: 0, endCenter: hot, endRadius: 250, options: [])
    ctx.restoreGState()

    // Thin inner edge so the body reads against light backgrounds.
    ctx.addPath(squircle)
    ctx.setStrokeColor(color(1, 1, 1, 0.22))
    ctx.setLineWidth(3)
    ctx.strokePath()

    return ctx.makeImage()!
}

func png(_ image: CGImage, side: Int, to url: URL) {
    let ctx = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

let master = render()
for base in [16, 32, 128, 256, 512] {
    png(master, side: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    png(master, side: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote AppIcon.icns" : "iconutil failed")
