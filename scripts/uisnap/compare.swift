// UI-snapshot pixel comparator — no third-party dependencies, just ImageIO +
// CoreGraphics (always present with Xcode). Compares two PNGs and writes a diff
// image highlighting the pixels that changed beyond a per-channel tolerance.
//
// Exit codes:  0 = within budget (pass)   1 = over budget (fail)   2 = usage /
// load / dimension error (fail). The last is deliberately a failure: a
// reference that no longer loads, or a screen whose size changed, is a
// regression, not a skip.
//
// usage:
//   compare <reference.png> <candidate.png> <diff.png> <tolerance> <maxFraction> [ignore x y w h]...
//   tolerance   : 0–255, max per-channel delta before a pixel counts as changed
//   maxFraction : 0–1, share of considered pixels allowed to change
//   ignore      : zero or more rectangles in 0–1 fractions of the image, masked
//                 out of the comparison (e.g. the watch's system clock corner)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func loadPixels(_ path: String) -> (px: [UInt8], w: Int, h: Int)? {
    guard let data = FileManager.default.contents(atPath: path),
          let src = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    // Fixed RGBA8, non-premultiplied: identical layout for both inputs so the
    // byte-for-byte compare is meaningful regardless of the source encoding.
    guard let ctx = CGContext(
        data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buffer, w, h)
}

func writePNG(_ px: [UInt8], w: Int, h: Int, to path: String) {
    var buffer = px
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ), let image = ctx.makeImage() else { return }
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
guard args.count >= 6 else {
    fail("usage: compare <ref.png> <cand.png> <diff.png> <tolerance> <maxFraction> [ignore x y w h]...")
}
let refPath = args[1], candPath = args[2], diffPath = args[3]
guard let tolerance = Int(args[4]), let maxFraction = Double(args[5]) else {
    fail("tolerance must be an int and maxFraction a double")
}

// Ignore rectangles, in fractions of the image.
var ignores: [(x: Double, y: Double, w: Double, h: Double)] = []
var i = 6
while i + 3 < args.count {
    if args[i] == "ignore", let x = Double(args[i+1]), let y = Double(args[i+2]),
       let w = Double(args[i+3]), let h = Double(args[i+4]) {
        ignores.append((x, y, w, h)); i += 5
    } else { i += 1 }
}

guard let ref = loadPixels(refPath) else { fail("cannot load reference: \(refPath)") }
guard let cand = loadPixels(candPath) else { fail("cannot load candidate: \(candPath)") }
guard ref.w == cand.w, ref.h == cand.h else {
    fail("DIMENSION_MISMATCH reference \(ref.w)x\(ref.h) vs candidate \(cand.w)x\(cand.h)")
}

let w = ref.w, h = ref.h
// Precompute masked rows/cols as pixel ranges.
let masks = ignores.map { r -> (x0: Int, y0: Int, x1: Int, y1: Int) in
    (Int(r.x * Double(w)), Int(r.y * Double(h)),
     Int((r.x + r.w) * Double(w)), Int((r.y + r.h) * Double(h)))
}
func masked(_ x: Int, _ y: Int) -> Bool {
    for m in masks where x >= m.x0 && x < m.x1 && y >= m.y0 && y < m.y1 { return true }
    return false
}

var diff = [UInt8](repeating: 0, count: w * h * 4)
var changed = 0
var considered = 0
for y in 0..<h {
    for x in 0..<w {
        let o = (y * w + x) * 4
        if masked(x, y) {
            // Masked pixels are painted a flat blue in the diff so the ignored
            // region is obvious, and excluded from the ratio.
            diff[o] = 20; diff[o+1] = 40; diff[o+2] = 90; diff[o+3] = 255
            continue
        }
        considered += 1
        let dr = abs(Int(ref.px[o]) - Int(cand.px[o]))
        let dg = abs(Int(ref.px[o+1]) - Int(cand.px[o+1]))
        let db = abs(Int(ref.px[o+2]) - Int(cand.px[o+2]))
        if max(dr, max(dg, db)) > tolerance {
            changed += 1
            diff[o] = 255; diff[o+1] = 0; diff[o+2] = 200; diff[o+3] = 255   // magenta
        } else {
            // Dimmed grayscale of the reference for context.
            let g = UInt8((Int(ref.px[o]) + Int(ref.px[o+1]) + Int(ref.px[o+2])) / 3 / 3)
            diff[o] = g; diff[o+1] = g; diff[o+2] = g; diff[o+3] = 255
        }
    }
}

let fraction = considered > 0 ? Double(changed) / Double(considered) : 0
let pass = fraction <= maxFraction
if !pass { writePNG(diff, w: w, h: h, to: diffPath) }

let pct = String(format: "%.4f", fraction * 100)
let budget = String(format: "%.4f", maxFraction * 100)
print("\(pass ? "PASS" : "FAIL") changed=\(pct)% budget=\(budget)% (\(changed)/\(considered) px)")
exit(pass ? 0 : 1)
