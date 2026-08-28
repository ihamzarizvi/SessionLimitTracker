#!/usr/bin/env swift
// Renders AppIcon.icns for Session Limit Tracker: a dark squircle with the usage
// ring and Claude-style burst. Pure CoreGraphics so it runs with Command Line Tools.
import AppKit
import CoreGraphics
import Foundation

func drawIcon(size: CGFloat) -> CGImage? {
    let px = Int(size)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS icon grid: content inset from the canvas edge.
    let inset = size * 0.085
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.2237                     // Big Sur squircle ratio
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(red: 0.055, green: 0.055, blue: 0.063, alpha: 1))
    ctx.fillPath()

    let c = CGPoint(x: size / 2, y: size / 2)
    let r = rect.width * 0.30
    let lw = rect.width * 0.085
    ctx.setLineCap(.round)

    // Track ring.
    ctx.setLineWidth(lw)
    ctx.setStrokeColor(CGColor(red: 0.30, green: 0.30, blue: 0.30, alpha: 1))
    ctx.addArc(center: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // Usage arc — 73%, clockwise from 12 o'clock.
    ctx.setStrokeColor(CGColor(red: 0.96, green: 0.30, blue: 0.12, alpha: 1))
    let start = CGFloat.pi / 2
    ctx.addArc(center: c, radius: r, startAngle: start,
               endAngle: start - .pi * 2 * 0.73, clockwise: true)
    ctx.strokePath()

    // Centre burst.
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(max(1, rect.width * 0.028))
    let inner = r * 0.30, outer = r * 0.60
    for i in 0..<12 {
        let a = CGFloat(i) / 12 * .pi * 2
        ctx.move(to: CGPoint(x: c.x + cos(a) * inner, y: c.y + sin(a) * inner))
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * outer, y: c.y + sin(a) * outer))
    }
    ctx.strokePath()

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let specs: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for (name, size) in specs {
    guard let img = drawIcon(size: size) else { continue }
    writePNG(img, to: out.appendingPathComponent("\(name).png"))
}
print("iconset written to \(out.path)")
