import CoreWLAN
import LiquidBarCore
import SwiftUI

/// The small grey first line of a two-line detail.
struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.barWhite.opacity(0.7))
            .lineLimit(1)
    }
}

/// A slim level bar, 0...1.
struct Meter: View {
    let value: Double
    var tint = Color.barWhite
    var width: CGFloat = 72

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.2))
            .frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: width * min(1, max(0, value)))
            }
    }
}

/// Scroll changes the level in steps of 2; the detail names the output device and shows the level.
struct VolumePill: View {
    let model: BarModel

    var body: some View {
        let volume = model.volume
        let level = volume.muted ? 0 : volume.level
        LivePill(id: "volume", pulse: volume) {
            Image(systemName: volume.symbol)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
        } detail: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Caption(text: volume.device)
                    Meter(value: Double(level) / 100)
                }
                .frame(minWidth: 72, alignment: .leading)
                Text("\(level)%")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, alignment: .trailing)
                    .contentTransition(.numericText(value: Double(level)))
            }
        }
        .animation(spring, value: level)
        .overlay {
            ScrollCatcher { steps in model.nudgeVolume(steps) }
        }
    }
}

/// Pulses on plug and unplug; the detail says how long the battery lasts or how long charging takes.
struct BatteryPill: View {
    let battery: BatteryState

    var body: some View {
        LivePill(id: "battery", pulse: battery.onAC) {
            HStack(spacing: 5) {
                Image(systemName: battery.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(battery.tint.color, Color.barWhite.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: battery.onAC)
                // Changes every few minutes at rest, so it swaps without a transition, like the clock.
                Text("\(battery.percent)%")
                    .font(.system(size: 12, weight: .bold))
            }
        } detail: {
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: battery.detail)
                Meter(value: Double(battery.percent) / 100, tint: battery.tint.color)
            }
        }
        .animation(spring, value: battery.onAC)
    }
}

/// Pulses when connectivity changes. The detail names the network and shows live throughput, sampled once a
/// second only while it is visible.
struct NetworkPill: View {
    let network: NetworkState

    var body: some View {
        LivePill(id: "wifi", pulse: network.kind) {
            Image(systemName: network.symbol)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
        } detail: {
            NetworkDetail(network: network)
        }
    }
}

private struct NetworkDetail: View {
    let network: NetworkState
    @State private var name: String?
    @State private var bars: Int?
    @State private var rates: (down: Double, up: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Caption(text: name ?? fallbackName)
                if name == nil, let bars {
                    Image(systemName: "wifi", variableValue: Double(bars) / 3)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.barWhite.opacity(0.7))
                }
            }
            if network.kind != .offline {
                Text("↓ \(throughputText(rates?.down ?? 0))   ↑ \(throughputText(rates?.up ?? 0))")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
        .task(id: network) { await sample() }
    }

    private var fallbackName: String {
        switch network.kind {
        case .wifi: "Wi-Fi"
        case .wired: "Ethernet"
        case .offline: "Offline"
        }
    }

    private func sample() async {
        if network.kind == .wifi, let wifi = CWWiFiClient.shared().interface() {
            // The SSID needs Location access; without it CoreWLAN returns nil and signal bars stand in.
            name = wifi.ssid()
            bars = signalBars(rssi: wifi.rssiValue())
        } else {
            name = nil
            bars = nil
        }
        guard let interface = network.interface, var last = interfaceBytes(interface) else { return }
        var lastTime = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let now = interfaceBytes(interface) else { return }
            let elapsed = Date().timeIntervalSince(lastTime)
            withAnimation(spring) {
                rates = (Double(now.received &- last.received) / elapsed, Double(now.sent &- last.sent) / elapsed)
            }
            last = now
            lastTime = Date()
        }
    }
}

/// The time at rest; hovering widens it to the long date with seconds ticking. Click opens the calendar, unless
/// `clicks` sets a command for `clock`.
struct ClockPill: View {
    let model: BarModel
    let screenFrame: CGRect
    let pillHeight: CGFloat
    @State private var frame = CGRect.zero

    var body: some View {
        let now = model.now
        LivePill(id: "clock", pulse: 0) { expanded in
            Group {
                if expanded {
                    // The seconds timer exists only while this view does.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let time = clockText(context.date, seconds: true)
                        ViewThatFits(in: .horizontal) {
                            Text("\(longDateText(context.date)) · \(time)")
                            Text("\(dateText(context.date)) · \(time)")
                            Text(time)
                        }
                        .contentTransition(.numericText())
                        .animation(spring, value: context.date)
                    }
                    .transition(.blurReplace)
                } else {
                    // No transition on the minute flip: animating it costs ~0.2s of CPU every minute at rest.
                    Text(clockText(now))
                        .fixedSize()
                        .transition(.blurReplace)
                }
            }
            .pill(height: pillHeight)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onTapGesture {
            if let command = model.config.clicks["clock"] {
                shell(command)
            } else {
                let top = screenFrame.maxY - model.config.height
                CalendarPopover.toggle(anchor: NSRect(x: screenFrame.minX + frame.minX, y: top, width: frame.width, height: model.config.height))
            }
        }
    }
}

/// Artwork and a live equalizer at rest; title, artist and transport controls in the detail. Pulses on track change.
/// It takes plain state so it can live anywhere, not only in the right island.
struct NowPlayingPill: View {
    let nowPlaying: NowPlaying
    let artwork: NSImage?
    let colors: [RGB]
    let control: (String) -> Void

    var body: some View {
        LivePill(id: "nowPlaying", pulse: nowPlaying.trackID) {
            HStack(spacing: 7) {
                Group {
                    if let artwork {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note")
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                // The artwork's colours drift slowly behind it while the track plays.
                .background {
                    if colors.count > 0 {
                        GradientDrift(colors: colors.map(\.color), moving: nowPlaying.playing)
                            .frame(width: 44, height: 30)
                            .blur(radius: 8)
                            .opacity(0.8)
                    }
                }
                .onTapGesture { shell("open -b \(nowPlaying.player.rawValue)") }
                Equalizer(playing: nowPlaying.playing)
                    .frame(width: 14, height: 14)
            }
        } detail: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Marquee(text: nowPlaying.title, font: .system(size: 11, weight: .bold), width: 150)
                    Marquee(text: nowPlaying.artist, font: .system(size: 10, weight: .semibold), width: 150)
                        .foregroundStyle(Color.barWhite.opacity(0.7))
                }
                HStack(spacing: 2) {
                    TransportButton(symbol: "backward.fill") { control("previous track") }
                    TransportButton(symbol: nowPlaying.playing ? "pause.fill" : "play.fill") { control("playpause") }
                    TransportButton(symbol: "forward.fill") { control("next track") }
                }
            }
        }
        .animation(spring, value: nowPlaying)
    }
}

private struct TransportButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .bold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 26, height: 24)
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
            .font(.system(size: 13, weight: bold ? .bold : .medium))
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background { if hovering { Capsule().fill(.white.opacity(0.14)) } }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture { open(frame) }
    }
}


/// Two colours sliding across each other, driven by Core Animation so it costs the bar no CPU.
struct GradientDrift: NSViewRepresentable {
    let colors: [Color]
    let moving: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(CAGradientLayer())
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let gradient = view.layer?.sublayers?.first as? CAGradientLayer else { return }
        let cgColors = (colors + colors).prefix(2).map { NSColor($0).cgColor }
        gradient.colors = cgColors + [cgColors[0]]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = view.bounds.insetBy(dx: -view.bounds.width, dy: 0)
        gradient.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        gradient.removeAllAnimations()
        guard moving else { return }
        let drift = CABasicAnimation(keyPath: "transform.translation.x")
        drift.fromValue = -view.bounds.width * 0.8
        drift.toValue = view.bounds.width * 0.8
        drift.duration = 5
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(drift, forKey: "drift")
    }
}

/// A band of light sweeping across a charging battery every few seconds, in Core Animation.
struct Shimmer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ShimmerView()
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    final class ShimmerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard let layer, bounds.width > 0 else { return }
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let band = CAGradientLayer()
            let clear = NSColor.white.withAlphaComponent(0).cgColor
            band.colors = [clear, NSColor.white.withAlphaComponent(0.32).cgColor, clear]
            band.startPoint = CGPoint(x: 0, y: 0.3)
            band.endPoint = CGPoint(x: 1, y: 0.7)
            band.frame = CGRect(x: -bounds.width * 0.5, y: 0, width: bounds.width * 0.5, height: bounds.height)
            layer.addSublayer(band)
            let sweep = CAKeyframeAnimation(keyPath: "position.x")
            sweep.values = [-bounds.width * 0.25, bounds.width * 1.25, bounds.width * 1.25]
            sweep.keyTimes = [0, 0.4, 1]
            sweep.duration = 3.2
            sweep.repeatCount = .infinity
            sweep.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear)]
            band.add(sweep, forKey: "sweep")
        }
    }
}
