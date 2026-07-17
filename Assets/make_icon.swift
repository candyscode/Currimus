// Renders the CURRIMUS app icon: the wordmark reduced to its C, drawn as an
// open running track; the runner is the dot closing the loop.
// Usage: swift make_icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let scale = size / 180

guard CommandLine.arguments.count > 1 else {
    fputs("usage: make_icon.swift <output.png>\n", stderr)
    exit(1)
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1
    )
}

// Ink background with a soft radial sheen from the upper left.
ctx.setFillColor(color(0x000000))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [color(0x1C1C1C), color(0x0A0A0A), color(0x000000)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawRadialGradient(
    gradient,
    startCenter: CGPoint(x: size * 0.28, y: size * 0.82), startRadius: 0,
    endCenter: CGPoint(x: size * 0.28, y: size * 0.82), endRadius: size * 1.3,
    options: .drawsAfterEndLocation
)

// The C — a circle with its right side open (±40°), stroked in Signal.
let center = CGPoint(x: 90 * scale, y: 90 * scale)
let radius = 52 * scale
ctx.setStrokeColor(color(0xFF4D00))
ctx.setLineWidth(20 * scale)
ctx.setLineCap(.round)
ctx.addArc(
    center: center, radius: radius,
    startAngle: 40 * .pi / 180, endAngle: -40 * .pi / 180, clockwise: false
)
ctx.strokePath()

// The runner closing the loop.
let dotAngle: CGFloat = -40 * .pi / 180
let dot = CGPoint(x: center.x + radius * cos(dotAngle), y: center.y + radius * sin(dotAngle))
ctx.setFillColor(color(0xF5F4F2))
ctx.fillEllipse(in: CGRect(x: dot.x - 10 * scale, y: dot.y - 10 * scale, width: 20 * scale, height: 20 * scale))

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("wrote \(CommandLine.arguments[1])")
