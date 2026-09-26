import Foundation

public struct RGB: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Hue, saturation and value, each 0...1.
    public var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        guard delta > 0 else { return (0, 0, maxC) }
        let h: Double =
            if maxC == r { ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { (b - r) / delta + 2 }
            else { (r - g) / delta + 4 }
        return ((h / 6 + 1).truncatingRemainder(dividingBy: 1), delta / maxC, maxC)
    }

    public init(h: Double, s: Double, v: Double) {
        let i = Int(h * 6) % 6, f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        (r, g, b) = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    }

    /// The colour as a tint for the fluid's rim: saturated enough to read as colour, never brighter than 72%.
    /// Darkened yellow turns olive, so yellows move to amber first.
    public var glassTint: RGB {
        var (h, s, v) = hsv
        if (0.1...0.2).contains(h) {
            h = 0.085
            s = max(s, 0.75)
        }
        return RGB(h: h, s: min(max(s, 0.45), 0.9), v: min(max(v, 0.45), 0.72))
    }
}

/// The dominant colours of an image given as RGBA bytes, most dominant first. Pixels that are transparent, grey or
/// near black do not count; the rest are grouped into twelve hue buckets weighted by saturation, and each returned
/// colour is the average of one bucket. Empty for a greyscale image.
public func palette(rgba: [UInt8], count: Int = 2) -> [RGB] {
    var sums = [(r: Double, g: Double, b: Double, weight: Double)](repeating: (0, 0, 0, 0), count: 12)
    for i in stride(from: 0, to: rgba.count - 3, by: 4) where rgba[i + 3] > 128 {
        let color = RGB(Double(rgba[i]) / 255, Double(rgba[i + 1]) / 255, Double(rgba[i + 2]) / 255)
        let (h, s, v) = color.hsv
        guard s > 0.25, v > 0.2 else { continue }
        let bucket = Int(h * 12) % 12
        sums[bucket].r += color.r * s
        sums[bucket].g += color.g * s
        sums[bucket].b += color.b * s
        sums[bucket].weight += s
    }
    return sums.filter { $0.weight > 0 }
        .sorted { $0.weight > $1.weight }
        .prefix(count)
        .map { RGB($0.r / $0.weight, $0.g / $0.weight, $0.b / $0.weight) }
}
