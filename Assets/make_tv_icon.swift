// Renders the tvOS Brand Assets: the layered app icon and the two Top Shelf
// images, from the same mark as `make_icon.swift` — the wordmark reduced to its
// C, drawn as an open running track, with the runner as the dot closing it.
//
// tvOS does not take a flat icon. The home screen icon is an *image stack*: two
// or more layers the system parallaxes apart as focus moves over the tile. So
// the mark is drawn in three passes — the ink sheen behind, the track, and the
// runner in front — instead of once into a square.
//
// Usage: swift Assets/make_tv_icon.swift TV/Assets.xcassets
//
// Regenerate after any change to the mark, and keep it in step with
// `make_icon.swift`; the two icons are the same logo at different aspect ratios.
import AppKit

// MARK: - Geometry

/// Which pass of the mark to draw. One enum so the sizes below stay in one
/// place and every layer of every size agrees about where the C sits.
enum Layer: String, CaseIterable {
    case back = "Back", middle = "Middle", front = "Front"
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draw one layer of the mark into `ctx` for a canvas of `size`.
///
/// The proportions are the square icon's, restated against the short edge so
/// the mark keeps its weight on a 5:3 tile: radius 52/180 and stroke 20/180 of
/// the artboard become a fraction of the height here.
func draw(_ layer: Layer, in ctx: CGContext, size: CGSize, markScale: CGFloat = 1) {
    let radius = size.height * 0.30 * markScale
    let lineWidth = radius * (20.0 / 52.0)
    let dotRadius = radius * (10.0 / 52.0)
    let center = CGPoint(x: size.width / 2, y: size.height / 2)
    let dotAngle: CGFloat = -40 * .pi / 180

    switch layer {
    case .back:
        // Ink with a soft radial sheen from the upper left, as on the phone.
        ctx.setFillColor(color(0x000000))
        ctx.fill(CGRect(origin: .zero, size: size))
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [color(0x1C1C1C), color(0x0A0A0A), color(0x000000)] as CFArray,
            locations: [0, 0.55, 1]
        )!
        let origin = CGPoint(x: size.width * 0.28, y: size.height * 0.82)
        ctx.drawRadialGradient(gradient, startCenter: origin, startRadius: 0,
                               endCenter: origin, endRadius: max(size.width, size.height) * 1.1,
                               options: .drawsAfterEndLocation)

    case .middle:
        // The C — a circle with its right side open (±40°), stroked in Signal.
        ctx.setStrokeColor(color(0xFF4D00))
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.addArc(center: center, radius: radius,
                   startAngle: 40 * .pi / 180, endAngle: dotAngle, clockwise: false)
        ctx.strokePath()

    case .front:
        // The runner closing the loop. Frontmost, so parallax moves it most.
        let dot = CGPoint(x: center.x + radius * cos(dotAngle),
                          y: center.y + radius * sin(dotAngle))
        ctx.setFillColor(color(0xF5F4F2))
        ctx.fillEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius,
                                   width: dotRadius * 2, height: dotRadius * 2))
    }
}

// MARK: - Rendering

func render(width: Int, height: Int, _ body: (CGContext, CGSize) -> Void) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body(NSGraphicsContext.current!.cgContext, CGSize(width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// A layer image. Only the back layer is opaque; the other two are transparent
/// so the stack composites — a layer that filled its own background would hide
/// everything behind it.
func layerImage(_ layer: Layer, width: Int, height: Int) -> Data {
    render(width: width, height: height) { ctx, size in
        draw(layer, in: ctx, size: size)
    }
}

/// A Top Shelf image: the whole mark flattened, held at a size that reads from
/// the sofa without filling the banner.
func topShelfImage(width: Int, height: Int) -> Data {
    render(width: width, height: height) { ctx, size in
        for layer in Layer.allCases { draw(layer, in: ctx, size: size, markScale: 0.78) }
    }
}

// MARK: - Catalogue

let fm = FileManager.default

guard CommandLine.arguments.count > 1 else {
    fputs("usage: make_tv_icon.swift <output.xcassets>\n", stderr)
    exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])

func write(_ data: Data, to url: URL) throws {
    try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    try write(data, to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]

/// One `.imagestack` — the layered icon at a single size. `scales` is the set
/// of asset scales the slot takes (the App Store icon is 1x only).
func makeImageStack(at url: URL, width: Int, height: Int, scales: [Int]) throws {
    try writeJSON([
        "info": info,
        // Front first: Asset Catalog lists an image stack's layers top-down.
        "layers": [["filename": "Front.imagestacklayer"],
                   ["filename": "Middle.imagestacklayer"],
                   ["filename": "Back.imagestacklayer"]]
    ], to: url.appendingPathComponent("Contents.json"))

    for layer in Layer.allCases {
        let layerURL = url.appendingPathComponent("\(layer.rawValue).imagestacklayer")
        try writeJSON(["info": info], to: layerURL.appendingPathComponent("Contents.json"))

        let contentURL = layerURL.appendingPathComponent("Content.imageset")
        var images: [[String: String]] = []
        for scale in scales {
            let name = scale == 1 ? "\(layer.rawValue).png" : "\(layer.rawValue)@\(scale)x.png"
            try write(layerImage(layer, width: width * scale, height: height * scale),
                      to: contentURL.appendingPathComponent(name))
            images.append(["filename": name, "idiom": "tv", "scale": "\(scale)x"])
        }
        try writeJSON(["images": images, "info": info],
                      to: contentURL.appendingPathComponent("Contents.json"))
    }
}

func makeTopShelf(at url: URL, width: Int, height: Int, prefix: String) throws {
    var images: [[String: String]] = []
    for scale in [1, 2] {
        let name = scale == 1 ? "\(prefix).png" : "\(prefix)@\(scale)x.png"
        try write(topShelfImage(width: width * scale, height: height * scale),
                  to: url.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "tv", "scale": "\(scale)x"])
    }
    try writeJSON(["images": images, "info": info], to: url.appendingPathComponent("Contents.json"))
}

// Rebuild from scratch, so a renamed slot cannot leave an orphan behind.
let brand = root.appendingPathComponent("App Icon & Top Shelf Image.brandassets")
if fm.fileExists(atPath: brand.path) { try fm.removeItem(at: brand) }

try writeJSON(["info": info], to: root.appendingPathComponent("Contents.json"))

try makeImageStack(at: brand.appendingPathComponent("App Icon.imagestack"),
                   width: 400, height: 240, scales: [1, 2])
try makeImageStack(at: brand.appendingPathComponent("App Icon - App Store.imagestack"),
                   width: 1280, height: 768, scales: [1])
try makeTopShelf(at: brand.appendingPathComponent("Top Shelf Image.imageset"),
                 width: 1920, height: 720, prefix: "TopShelf")
try makeTopShelf(at: brand.appendingPathComponent("Top Shelf Image Wide.imageset"),
                 width: 2320, height: 720, prefix: "TopShelfWide")

try writeJSON([
    "assets": [
        ["filename": "App Icon.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "400x240"],
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv",
         "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv",
         "role": "top-shelf-image", "size": "1920x720"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
         "role": "top-shelf-image-wide", "size": "2320x720"]
    ],
    "info": info
], to: brand.appendingPathComponent("Contents.json"))

print("wrote \(brand.path)")
