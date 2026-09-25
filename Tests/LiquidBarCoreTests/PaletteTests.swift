import LiquidBarCore
import Testing

private func pixels(_ colors: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] {
    colors.flatMap { [$0.0, $0.1, $0.2, $0.3] }
}

@Test func dominantColourIgnoresGreysAndTransparency() {
    // A Spotify-like icon: mostly green, black glyph, transparent corners, a little white.
    let icon = pixels(Array(repeating: (30, 215, 96, 255), count: 10) + Array(repeating: (0, 0, 0, 255), count: 20)
                      + Array(repeating: (255, 0, 0, 0), count: 30) + [(255, 255, 255, 255), (40, 200, 90, 255)])
    let colors = palette(rgba: icon)
    #expect(colors.count == 1)
    let green = try! #require(colors.first)
    #expect(Int((green.r * 255).rounded()) == 31)
    #expect(Int((green.g * 255).rounded()) == 214)
    #expect(Int((green.b * 255).rounded()) == 95)
    #expect(palette(rgba: pixels([(128, 128, 128, 255), (0, 0, 0, 255), (250, 250, 250, 255)])) == [])
}

@Test func twoColourPaletteForArtwork() {
    let art = pixels(Array(repeating: (88, 101, 242, 255), count: 6) + Array(repeating: (255, 122, 89, 255), count: 4))
    let bytes = palette(rgba: art).map { [$0.r, $0.g, $0.b].map { Int(($0 * 255).rounded()) } }
    #expect(bytes == [[88, 101, 242], [255, 122, 89]])
}

@Test func glassTintStaysDarkEnoughForWhiteText() {
    let yellow = RGB(1, 0.9, 0.2).glassTint
    #expect(yellow.hsv.v == 0.72)
    #expect(abs(yellow.hsv.h - 0.085) < 1e-9)
    let red = RGB(0.9, 0.2, 0.2).glassTint
    #expect(abs(red.hsv.h - 0) < 1e-9)
    let pale = RGB(0.8, 0.8, 0.9).glassTint
    #expect(abs(pale.hsv.s - 0.45) < 1e-9)
    let navy = RGB(0.05, 0.05, 0.3).glassTint
    #expect(abs(navy.hsv.v - 0.45) < 1e-9)
    #expect(abs(navy.hsv.h - RGB(0.05, 0.05, 0.3).hsv.h) < 1e-9)
}
