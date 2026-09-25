import AppKit
import LiquidBarCore
import SwiftUI

extension NSImage {
    /// Dominant colours from a 16x16 downsample, most dominant first.
    func palette(count: Int = 2) -> [RGB] {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        context.interpolationQuality = .medium
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        return LiquidBarCore.palette(rgba: pixels, count: count)
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

extension AppIcons {
    private static var tints: [String: Color?] = [:]

    /// The glass tint an app's icon suggests, computed once per app; nil for a greyscale icon.
    static func tint(_ bundleID: String) -> Color? {
        if let tint = tints[bundleID] { return tint }
        let tint = icon(bundleID).palette(count: 1).first?.glassTint.color
        tints[bundleID] = tint
        return tint
    }
}

/// The light tick of a pressed control, on trackpads that have a haptic engine.
func haptic() {
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
}
