// Renders the app icon: docs/images/icon.png (1024 px master) and Support/AppIcon.icns.
// Run from the repo root with `make icon`.
//
// The icon is the workspace selector as the bar draws it: a capsule of glass with a workspace's app, the lens a few
// points inside it around the focused workspace's app, the second of four. Glass is built
// from a mask of its shape: what is behind it is blurred and a little magnified, and light
// catches the rim at the top left and the bottom right.
import AppKit
import CoreImage
import SwiftUI

let S = 1024
let ci = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hex(_ v: Int, _ a: CGFloat = 1) -> CGColor { rgb(CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255, a) }
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath { RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r).cgPath }
func capsule(_ r: CGRect) -> CGPath { squircle(r, min(r.width, r.height) / 2) }
func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGPath { CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil) }
let body = squircle(CGRect(x: 100, y: 100, width: 824, height: 824), 185)

/// A top-left-origin RGBA bitmap.
func color(_ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(S)); c.scaleBy(x: 1, y: -1)
    draw(c); return c.makeImage()!
}
/// A top-left-origin gray bitmap, black where nothing is drawn: a mask.
func gray(_ draw: (CGContext) -> Void) -> CGImage {
    let c = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    c.setFillColor(gray: 0, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
    c.translateBy(x: 0, y: CGFloat(S)); c.scaleBy(x: 1, y: -1)
    c.setFillColor(gray: 1, alpha: 1)
    draw(c); return c.makeImage()!
}
let frame = CGRect(x: 0, y: 0, width: S, height: S)
func blur(_ image: CGImage, _ radius: CGFloat) -> CIImage {
    CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: frame)
}
/// 1 where the field is above `t`, with an edge `1 / k` wide.
func threshold(_ field: CIImage, _ t: CGFloat, _ k: CGFloat = 40) -> CIImage {
    let bias = 0.5 - t * k
    return field.applyingFilter("CIColorMatrix", parameters: [
        "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0), "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
    ]).applyingFilter("CIColorClamp")
}
func mask(_ image: CIImage) -> CGImage {
    let c = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    c.draw(ci.createCGImage(image, from: frame)!, in: frame)
    return c.makeImage()!
}
func rgba(_ image: CIImage) -> CGImage { ci.createCGImage(image, from: frame, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)! }
/// Images made here are already top-left; drawing them into a flipped context needs the flip undone.
func put(_ c: CGContext, _ image: CGImage, in rect: CGRect = frame) {
    c.saveGState(); c.translateBy(x: rect.minX, y: rect.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(image, in: CGRect(origin: .zero, size: rect.size)); c.restoreGState()
}
func clipped(_ c: CGContext, to m: CGImage, offset: CGPoint = .zero, _ draw: () -> Void) {
    c.saveGState(); c.translateBy(x: offset.x, y: CGFloat(S) + offset.y); c.scaleBy(x: 1, y: -1)
    c.clip(to: frame, mask: m)
    c.scaleBy(x: 1, y: -1); c.translateBy(x: -offset.x, y: -CGFloat(S) - offset.y)
    draw(); c.restoreGState()
}
func gradient(_ c: CGContext, _ colors: [CGColor], _ stops: [CGFloat], from: CGPoint, to: CGPoint) {
    c.drawLinearGradient(CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: stops)!, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
func glow(_ c: CGContext, _ color: CGColor, at p: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: nil, colors: [color, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}

/// The backdrop, the social preview's ocean: deep blue to teal, with a violet, a light blue and an aqua glow for the
/// glass to bend.
struct Palette { let base: [CGColor]; let glows: [(CGColor, CGPoint, CGFloat)] }
let ocean = Palette(base: [hex(0x0B2A6F), hex(0x1468D4), hex(0x21C7C0)],
                    glows: [(hex(0x7A5CFF, 0.6), CGPoint(x: 150, y: 130), 470), (hex(0x3FA8FF, 0.5), CGPoint(x: 600, y: 350), 360), (hex(0x5BE6D8, 0.6), CGPoint(x: 840, y: 924), 470)])

/// The backdrop without the body's clip, so glass can blur and magnify it.
func backdrop(_ p: Palette) -> CGImage {
    color { c in
        gradient(c, p.base, [0, 0.5, 1], from: CGPoint(x: 150, y: 100), to: CGPoint(x: 880, y: 924))
        for (col, at, r) in p.glows { glow(c, col, at: at, radius: r) }
    }
}

struct Glass {
    /// How far the shapes melt into each other before the edge is taken.
    var melt: CGFloat = 0
    var tint: CGFloat = 0.12
    var shapes: (CGContext) -> Void
}

func render(_ palette: Palette, _ layers: [Glass], glyphs: (CGContext) -> Void) -> CGImage {
    let bg = backdrop(palette)
    return color { c in
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
        c.addPath(body); c.setFillColor(palette.base[1]); c.fillPath()
        c.restoreGState()
        c.addPath(body); c.clip()
        put(c, bg)
        // A soft light from the top left on the whole tile.
        gradient(c, [rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)], [0, 1], from: CGPoint(x: 100, y: 100), to: CGPoint(x: 560, y: 620))
        var under = bg
        for layer in layers {
            let raw = gray(layer.shapes)
            let shape = layer.melt > 0 ? mask(threshold(blur(raw, layer.melt), 0.5, 30)) : raw
            let field = blur(shape, 9)
            let inside = mask(threshold(field, 0.5))
            let rim = mask(threshold(field, 0.5).applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": threshold(field, 0.8)]))
            let lip = mask(threshold(field, 0.8).applyingFilter("CIDifferenceBlendMode", parameters: ["inputBackgroundImage": threshold(field, 0.97, 12)]))
            // Its shadow on what is under it.
            clipped(c, to: mask(blur(shape, 26)), offset: CGPoint(x: 0, y: 22)) { c.setFillColor(rgb(0.03, 0.02, 0.25, 0.55)); c.fill(frame) }
            clipped(c, to: inside) {
                // What is behind, blurred and a little magnified, as thick glass bends it.
                let zoom: CGFloat = 1.1
                put(c, rgba(blur(under, 16)), in: frame.insetBy(dx: -CGFloat(S) * (zoom - 1) / 2, dy: -CGFloat(S) * (zoom - 1) / 2))
                c.setFillColor(rgb(1, 1, 1, layer.tint)); c.fill(frame)
                gradient(c, [rgb(1, 1, 1, 0.30), rgb(1, 1, 1, 0.02), rgb(1, 1, 1, 0.14)], [0, 0.5, 1], from: CGPoint(x: 0, y: 150), to: CGPoint(x: 0, y: 900))
            }
            // Light catches the edge at the top left and again at the bottom right.
            clipped(c, to: lip) { gradient(c, [rgb(1, 1, 1, 0.30), rgb(1, 1, 1, 0.0), rgb(1, 1, 1, 0.22)], [0, 0.5, 1], from: CGPoint(x: 150, y: 150), to: CGPoint(x: 880, y: 880)) }
            clipped(c, to: rim) { gradient(c, [rgb(1, 1, 1, 0.95), rgb(1, 1, 1, 0.28), rgb(1, 1, 1, 0.8)], [0, 0.5, 1], from: CGPoint(x: 200, y: 180), to: CGPoint(x: 820, y: 860)) }
            under = c.makeImage().map { snapshot in color { put($0, flipped(snapshot)) } } ?? under
        }
        c.setShadow(offset: CGSize(width: 0, height: 6), blur: 14, color: rgb(0.05, 0.03, 0.3, 0.35))
        glyphs(c)
    }
}
/// A context snapshot is bottom-left; this turns it top-left like the other images here.
func flipped(_ image: CGImage) -> CGImage {
    let c = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.translateBy(x: 0, y: CGFloat(S)); c.scaleBy(x: 1, y: -1); c.draw(image, in: frame); return c.makeImage()!
}
func white(_ c: CGContext, _ path: CGPath, _ alpha: CGFloat = 1) { c.addPath(path); c.setFillColor(rgb(1, 1, 1, alpha)); c.fillPath() }
func fill(_ c: CGContext, _ path: CGPath) { c.addPath(path); c.fillPath() }


let bar = CGRect(x: 112, y: 396, width: 800, height: 232), lens = CGRect(x: 305, y: 418, width: 220, height: 188)
let icon = render(ocean, [
    Glass(shapes: { c in fill(c, capsule(bar)) }),
    Glass(tint: 0.22, shapes: { c in fill(c, capsule(lens)) }),
]) { c in
    func app(_ x: CGFloat, _ size: CGFloat, _ alpha: CGFloat) {
        white(c, squircle(CGRect(x: x - size / 2, y: bar.midY - size / 2, width: size, height: size), size * 0.26), alpha)
    }
    let size = bar.height * 0.44
    app(222, size, 0.8)
    app(lens.midX, size, 1)
    app(608, size, 0.8)
    app(802, size, 0.8)
}

func writePNG(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
/// The master scaled down. The blurs need the full size, so the small sizes are not drawn on their own.
func scaled(_ px: Int) -> CGImage {
    let c = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.draw(icon, in: CGRect(x: 0, y: 0, width: px, height: px))
    return c.makeImage()!
}

writePNG(icon, "docs/images/icon.png")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset").path
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    writePNG(scaled(size), "\(iconset)/icon_\(size)x\(size).png")
    writePNG(scaled(size * 2), "\(iconset)/icon_\(size)x\(size)@2x.png")
}
let iconutil = try! Process.run(URL(fileURLWithPath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconset, "-o", "Support/AppIcon.icns"])
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
