import LiquidBarCore
import SwiftUI

/// A slim battery filled to the level, then the percentage unless turned off. A bolt shows only while charging.
struct BatteryLabel: View {
    let battery: BatteryState
    let percent: Bool

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 1.5) {
                if battery.charging { Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold)) }
                BatteryGlyph(level: Double(battery.percent) / 100, fill: battery.tint.color)
            }
            // Changes every few minutes at rest, so it swaps without a transition, like the clock.
            if percent { Text("\(battery.percent)%") }
        }
        .animation(spring, value: battery.charging)
    }
}

struct BatteryGlyph: View {
    let level: Double
    let fill: Color

    var body: some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(Color.barWhite.opacity(0.45), lineWidth: 1)
                .frame(width: 23, height: 12)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.75)
                        .fill(fill)
                        .frame(width: max(2, 19 * level), height: 8)
                        .padding(.leading, 2)
                }
            RoundedRectangle(cornerRadius: 1).fill(Color.barWhite.opacity(0.45)).frame(width: 1.5, height: 4)
        }
    }
}

/// Artwork and a live equalizer, with the title and artist between them while a new track shows. A click opens the
/// player.
struct NowPlayingLabel: View {
    let nowPlaying: NowPlaying
    let artwork: NSImage?
    var showsTitle = false

    var body: some View {
        HStack(spacing: 6) {
            Artwork(image: artwork, size: 18, radius: 4)
            if showsTitle {
                Text([nowPlaying.title, nowPlaying.artist].filter { !$0.isEmpty }.joined(separator: " · "))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 220)
                    .transition(.blurReplace)
            }
            Equalizer(playing: nowPlaying.playing)
                .frame(width: 14, height: 14)
        }
        .onTapGesture { shell("open -b \(nowPlaying.player.rawValue)") }
    }
}

struct Artwork: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// One line of text that scrolls back and forth when it is wider than `width`. It only animates while visible.
struct Marquee: View {
    let text: String
    let font: Font
    let width: CGFloat
    @State private var textWidth: CGFloat = 0
    @State private var scrolled = false

    var body: some View {
        let overflow = max(0, textWidth - width)
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            .offset(x: scrolled ? -overflow : 0)
            .frame(width: min(textWidth, width), alignment: .leading)
            .clipped()
            .task(id: overflow) {
                scrolled = false
                guard overflow > 0 else { return }
                // Hold, glide to the end at 30pt/s, hold, glide back.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.linear(duration: overflow / 30)) { scrolled.toggle() }
                    try? await Task.sleep(for: .seconds(overflow / 30))
                }
            }
    }
}

/// Four bars bouncing while playing, resting low when paused. Core Animation runs the bounce in the render server,
/// so a playing track costs the bar no CPU; a SwiftUI symbol effect redraws every frame on the main thread.
struct Equalizer: NSViewRepresentable {
    let playing: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        for index in 0..<4 {
            let bar = CALayer()
            bar.backgroundColor = NSColor(Color.barGreen).cgColor
            bar.cornerRadius = 1
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: CGFloat(index) * 3.5 + 0.5, y: 1, width: 2.2, height: 12)
            view.layer?.addSublayer(bar)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        for (index, bar) in (view.layer?.sublayers ?? []).enumerated() {
            bar.removeAllAnimations()
            bar.backgroundColor = NSColor(playing ? Color.barGreen : Color.barWhite.opacity(0.5)).cgColor
            bar.transform = CATransform3DMakeScale(1, playing ? 1 : 0.25, 1)
            guard playing else { continue }
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.2
            bounce.toValue = 1
            bounce.duration = [0.42, 0.31, 0.5, 0.37][index]
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(bounce, forKey: "bounce")
        }
    }
}

/// The front app's menu titles, the app's own menu first and in bold, like the native menu bar. Each opens a native
/// dropdown of that menu. Titles that do not fit beside the notch move into a trailing "»" title's menu.
struct MenuStrip: View {
    let titles: [AppMenuTitle]
    let openTitle: Int?
    let open: (_ id: Int, _ columns: [MenuColumn]) -> Void
    @Environment(\.bar) private var bar
    @State private var frames: [Int: CGRect] = [:]
    @State private var hovered: Int?
    @State private var originX: CGFloat = 0
    private static let overflowID = -1

    var body: some View {
        // The island ends 8pt short of the notch, counting the strip's own hit area.
        let budget = bar.left.map { $0 - 8 - originX } ?? .infinity
        let fit = menuTitlesThatFit(
            widths: titles.map { Self.width($0.title, bold: $0.id == titles.first?.id) },
            budget: budget,
            overflowWidth: Self.width("»", bold: false)
        )
        let overflow = Array(titles[fit...])
        HStack(spacing: 0) {
            ForEach(titles[..<fit]) { title in
                self.title(title.title, id: title.id, bold: title.id == titles.first?.id, overflow: overflow)
            }
            if !overflow.isEmpty { self.title("»", id: Self.overflowID, bold: false, overflow: overflow) }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { originX = $0 }
    }

    private func title(_ text: String, id: Int, bold: Bool, overflow: [AppMenuTitle]) -> some View {
        Text(text)
            .font(.system(size: 12, weight: bold ? .bold : .medium))
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 18)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames[id] = $0 }
            .background { RoundedRectangle(cornerRadius: 9).fill(.white.opacity((openTitle ?? hovered) == id ? 0.12 : 0)) }
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .onHover { inside in
                if inside { hovered = id } else if hovered == id { hovered = nil }
            }
            .onTapGesture {
                haptic()
                open(id, columns(overflow: overflow))
            }
    }

    private func columns(overflow: [AppMenuTitle]) -> [MenuColumn] {
        let shown = titles.filter { title in !overflow.contains { $0.id == title.id } }
        let menus = shown.map { title in (title.id, { AppMenus.menu(for: title) }) }
            + (overflow.isEmpty ? [] : [(Self.overflowID, { AppMenus.overflowMenu(overflow) })])
        return menus.compactMap { id, menu in frames[id].map { MenuColumn(id: id, rect: bar.column(under: $0), menu: menu) } }
    }

    /// A title's width in the strip, text and padding.
    private static func width(_ text: String, bold: Bool) -> Double {
        let font = NSFont.systemFont(ofSize: 12, weight: bold ? .bold : .medium)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width) + 14
    }
}
