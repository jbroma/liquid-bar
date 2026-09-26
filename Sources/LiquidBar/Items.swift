import CoreWLAN
import LiquidBarCore
import SwiftUI

/// A slim level bar, 0...1.
struct Meter: View {
    let value: Double
    var tint = Color.barWhite
    var width: CGFloat = 48
    var height: CGFloat = 4

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.2))
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: width * min(1, max(0, value)))
            }
    }
}

/// The level symbol and percentage. The symbol bounces on plug and unplug.
struct BatteryLabel: View {
    let battery: BatteryState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: battery.symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(battery.tint.color, Color.barWhite.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: battery.onAC)
            // Changes every few minutes at rest, so it swaps without a transition, like the clock.
            Text("\(battery.percent)%")
                .font(.system(size: 11, weight: .bold))
        }
        .animation(spring, value: battery.onAC)
    }
}

/// Artwork and a live equalizer. A click opens the player.
struct NowPlayingLabel: View {
    let nowPlaying: NowPlaying
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            Artwork(image: artwork, size: 18, radius: 4)
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

struct TransportButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 22, height: 20)
            .background { if hovering { Capsule().fill(.white.opacity(0.14)) } }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
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
/// dropdown of that menu.
struct MenuStrip: View {
    let titles: [AppMenuTitle]
    let open: (AppMenuTitle, CGRect) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles) { title in
                MenuTitleButton(title: title, bold: title.id == titles.first?.id) { open(title, $0) }
            }
        }
    }
}

private struct MenuTitleButton: View {
    let title: AppMenuTitle
    let bold: Bool
    let open: (CGRect) -> Void
    @State private var hovering = false
    @State private var frame = CGRect.zero

    var body: some View {
        Text(title.title)
            .font(.system(size: 12, weight: bold ? .bold : .medium))
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background { if hovering { Capsule().fill(.white.opacity(0.14)) } }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture { open(frame) }
    }
}
