// Renders the app icon: docs/images/icon.png (1024 px master) and Support/AppIcon.icns.
// Run from the repo root with `make icon`.
import AppKit
import SwiftUI

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func squircle(_ r: CGRect, _ radius: CGFloat) -> CGPath { RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: r).cgPath }
func capsule(_ r: CGRect) -> CGPath { squircle(r, r.height / 2) }

/// Draws the icon in a 1024-point space with a top-left origin, scaled to `px` pixels. Each size is drawn from the
/// vectors rather than downsampled, so the small sizes stay sharp.
func render(_ px: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // Apple's macOS grid: an 824 pt body centred on the 1024 canvas, leaving room for the shadow.
    let body = squircle(CGRect(x: 100, y: 100, width: 824, height: 824), 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0.2, 0.1, 0.6))
    ctx.fillPath()
    ctx.restoreGState()

    // The wallpaper from the screenshots: violet to deep blue, with a lighter sweep and its bright rim.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let wallpaper = CGGradient(colorsSpace: nil, colors: [rgb(0.45, 0.25, 0.92), rgb(0.20, 0.12, 0.78), rgb(0.05, 0.12, 0.55)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(wallpaper, start: CGPoint(x: 150, y: 100), end: CGPoint(x: 880, y: 924), options: [])
    let rim = CGMutablePath()
    rim.move(to: CGPoint(x: 230, y: 924))
    rim.addQuadCurve(to: CGPoint(x: 924, y: 540), control: CGPoint(x: 470, y: 560))
    let sweep = rim.mutableCopy()!
    sweep.addLine(to: CGPoint(x: 924, y: 924))
    sweep.closeSubpath()
    ctx.addPath(sweep)
    ctx.setFillColor(rgb(0.25, 0.45, 1, 0.35))
    ctx.fillPath()
    ctx.addPath(rim)
    ctx.setStrokeColor(rgb(1, 1, 1, 0.55))
    ctx.setLineWidth(7)
    ctx.strokePath()
    ctx.restoreGState()

    func glass(_ rect: CGRect, fill: CGFloat, shadow: Bool) {
        let path = capsule(rect)
        if shadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -rect.height * 0.08), blur: rect.height * 0.25, color: rgb(0.02, 0.02, 0.2, 0.45))
            ctx.addPath(path)
            ctx.setFillColor(rgb(1, 1, 1, fill))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let sheen = CGGradient(colorsSpace: nil, colors: [rgb(1, 1, 1, 0.38), rgb(1, 1, 1, 0.04), rgb(1, 1, 1, 0.12)] as CFArray, locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(sheen, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        ctx.restoreGState()
        ctx.addPath(path)
        ctx.setStrokeColor(rgb(1, 1, 1, 0.6))
        ctx.setLineWidth(rect.height * 0.035)
        ctx.strokePath()
    }
    func white(_ path: CGPath, _ alpha: CGFloat) {
        ctx.addPath(path)
        ctx.setFillColor(rgb(1, 1, 1, alpha))
        ctx.fillPath()
    }
    func dot(_ x: CGFloat, _ r: CGFloat, _ alpha: CGFloat) { white(CGPath(ellipseIn: CGRect(x: x - r, y: 335 - r, width: 2 * r, height: 2 * r), transform: nil), alpha) }

    // A zoomed-in bar: the focused workspace pill with two apps, an empty workspace, and a status pill.
    glass(CGRect(x: 150, y: 210, width: 724, height: 250), fill: 0.30, shadow: true)
    glass(CGRect(x: 190, y: 250, width: 290, height: 170), fill: 0.34, shadow: false)
    dot(275, 38, 1)
    dot(395, 38, 0.75)
    dot(555, 30, 0.55)
    white(capsule(CGRect(x: 640, y: 309, width: 180, height: 52)), 1)

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ path: String) {
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

writePNG(render(1024), "docs/images/icon.png")
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset").path
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    writePNG(render(size), "\(iconset)/icon_\(size)x\(size).png")
    writePNG(render(size * 2), "\(iconset)/icon_\(size)x\(size)@2x.png")
}
let iconutil = try! Process.run(URL(fileURLWithPath: "/usr/bin/iconutil"), arguments: ["-c", "icns", iconset, "-o", "Support/AppIcon.icns"])
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
