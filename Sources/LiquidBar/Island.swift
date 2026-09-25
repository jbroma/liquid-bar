import AppKit
import LiquidBarCore
import SwiftUI

/// The island's own spring: a touch bouncier than the bar's, like the Dynamic Island.
let islandSpring = Animation.spring(response: 0.44, dampingFraction: 0.76)

/// Every size the island takes, from one place: the view draws these and the panel sizes its window from them.
struct IslandGeometry {
    /// The hardware notch in points; zero width on a screen without one.
    let notch: CGSize
    /// The bar's height: an active island reaches down to the pills' bottom edge and centers its ears on their midline.
    var barHeight: CGFloat = 40

    var band: CGFloat { barHeight - 3 }

    nonisolated static let flare: CGFloat = 6
    static let rowHeight: CGFloat = 46
    static let cardHeight: CGFloat = 64

    func earWidth(_ content: IslandContent) -> CGFloat {
        switch content {
        case .idle: 0
        case .agents: 118
        case .nowPlaying: 44
        }
    }

    func size(_ content: IslandContent, _ presentation: IslandPresentation, rows: Int, card: Bool) -> CGSize {
        // Idle, the shape waits well inside the hardware notch, flares and all, so nothing shows.
        let hidden = CGSize(width: max(0, notch.width - 40), height: max(0, notch.height - 8))
        let ears = content == .idle ? hidden : CGSize(width: notch.width + 2 * earWidth(content), height: band)
        switch presentation {
        case .ears: return ears
        case .pulse: return CGSize(width: max(ears.width, 390), height: band + 50)
        case .expanded:
            let list = CGFloat(rows) * Self.rowHeight + (card ? Self.cardHeight : 0) + (rows > 0 && card ? 4 : 0)
            return CGSize(width: max(ears.width, 440), height: band + 6 + list + 6)
        }
    }

    func radius(_ presentation: IslandPresentation) -> CGFloat {
        switch presentation {
        case .ears: 14
        case .pulse: 24
        case .expanded: 30
        }
    }
}

/// One island's presentation. Pulses come from the model; hover from the island's shape.
@Observable
final class IslandController {
    private(set) var presentation: IslandPresentation = .ears
    @ObservationIgnored private var presenter = IslandPresenter()
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored var canExpand: () -> Bool = { false }

    func hover(_ inside: Bool) {
        presenter.hover(inside, at: Date())
        update()
    }

    func dismiss() {
        presenter.dismiss()
        update()
    }

    func pulse(_ pulse: IslandPulse) {
        presenter.pulse(pulse, at: Date())
        update()
    }

    func update() {
        let (next, recheck) = presenter.presentation(at: Date(), current: presentation, canExpand: canExpand())
        if next != presentation { withAnimation(islandSpring) { presentation = next } }
        timer?.cancel()
        guard let recheck else { return }
        timer = Task {
            try? await Task.sleep(for: .seconds(recheck.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            update()
        }
    }
}

extension BarModel {
    var islandContent: IslandContent { IslandContent(agents: agents, nowPlaying: nowPlaying) }
    var islandThreadList: [AgentThread] { islandThreads(agents, now: Date()) }
}

/// A borderless panel hugging the notch, above the bar. Its frame follows the island's shape (growing at once,
/// shrinking after the spring settles), so the island receives hover itself and never blocks clicks beside it.
/// The SwiftUI view inside keeps one fixed size pinned to the top: resizing it mid-animation would re-lay it out
/// and throw the shape off its position for a few frames.
final class IslandPanel: NSPanel {
    let model: BarModel
    let controller = IslandController()
    let geometry: IslandGeometry
    private let notchCenter: CGFloat
    private let screenTop: CGFloat
    private var shrink: Task<Void, Never>?
    private var host: NSView?

    init(screen: NSScreen, model: BarModel, barHeight: CGFloat) {
        self.model = model
        let left = screen.auxiliaryTopLeftArea?.width
        let right = screen.auxiliaryTopRightArea?.width
        let notchWidth = left.flatMap { l in right.map { screen.frame.width - l - $0 } } ?? 0
        geometry = IslandGeometry(notch: CGSize(width: notchWidth, height: screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32),
                                  barHeight: barHeight)
        notchCenter = screen.frame.minX + (left.map { $0 + notchWidth / 2 } ?? screen.frame.width / 2)
        screenTop = screen.frame.maxY
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        controller.canExpand = { [model] in !model.islandThreadList.isEmpty || model.nowPlaying != nil }
        let host = NSHostingView(rootView: IslandView(model: model, controller: controller, geometry: geometry))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.maxSize)
        let container = NSView(frame: host.frame)
        container.addSubview(host)
        contentView = container
        self.host = host
        follow()
        orderFrontRegardless()
    }

    static let maxSize = CGSize(width: 560, height: 520)

    private var targetSize: CGSize {
        geometry.size(model.islandContent, controller.presentation, rows: model.islandThreadList.count, card: model.nowPlaying != nil)
    }

    private func follow() {
        let size = withObservationTracking { targetSize } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        let target = frame(for: size)
        shrink?.cancel()
        if target.width >= frame.width && target.height >= frame.height {
            place(target)
        } else {
            place(frame.union(target))
            shrink = Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                place(target)
            }
        }
    }

    /// Moves the window and keeps the view's top center on the notch.
    private func place(_ rect: NSRect) {
        setFrame(rect, display: true)
        host?.setFrameOrigin(NSPoint(x: notchCenter - Self.maxSize.width / 2 - rect.minX, y: rect.height - Self.maxSize.height))
    }

    private func frame(for size: CGSize) -> NSRect {
        // Room for the flares, and below and beside a pulse or the panel for its shadow.
        let margin: CGFloat = size.height > geometry.band ? 28 : 0
        let width = size.width + 2 * (IslandGeometry.flare + margin)
        let height = size.height + margin
        return NSRect(x: (notchCenter - width / 2).rounded(), y: screenTop - height, width: width.rounded(), height: height)
    }
}

/// The black shape grown out of the notch: ears at rest, a taller pill for a pulse, a panel on hover.
struct IslandView: View {
    let model: BarModel
    let controller: IslandController
    let geometry: IslandGeometry

    var body: some View {
        let content = model.islandContent
        let presentation = controller.presentation
        let threads = model.islandThreadList
        let size = geometry.size(content, presentation, rows: threads.count, card: model.nowPlaying != nil)
        let shape = IslandShape(bottomRadius: geometry.radius(presentation))
        ZStack(alignment: .top) {
            if content == .idle && presentation == .expanded {
                // Dropped down from the bare notch: name what the panel lists.
                HStack {
                    Text(threads.isEmpty ? "Now Playing" : "T3 Code")
                    Spacer()
                    if !threads.isEmpty { Text("\(threads.count) recent") }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.barWhite.opacity(0.5))
                .padding(.horizontal, 18)
                .frame(height: geometry.barHeight)
                .transition(.opacity)
            } else {
                EarsRow(content: content, notchWidth: geometry.notch.width, earWidth: geometry.earWidth(content), height: geometry.barHeight,
                        artwork: model.artwork)
            }
            if case .pulse(let pulse) = presentation {
                PulseRow(pulse: pulse, artwork: model.artwork)
                    .frame(height: 50)
                    .padding(.top, geometry.band)
                    .transition(.blurReplace.combined(with: .scale(0.85, anchor: .top)).combined(with: .opacity))
            }
            if presentation == .expanded {
                IslandPanelContent(model: model, threads: threads, open: open)
                    .padding(.top, geometry.band + 6)
                    .transition(.blurReplace.combined(with: .scale(0.92, anchor: .top)).combined(with: .opacity))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(.black)
        .clipShape(shape)
        // Below the bar the island floats over windows, often dark ones: a soft shadow and a hairline that fades in
        // from the bar's edge give it an outline without drawing a line along the top of the screen.
        .background(shape.fill(.black).shadow(color: .black.opacity(presentation == .ears ? 0 : 0.5), radius: 16, y: 8))
        .overlay { IslandOutline(shape: shape, fadeIn: geometry.band / size.height).opacity(presentation == .ears ? 0 : 1) }
        .contentShape(shape)
        .onHover { controller.hover($0) }
        .onTapGesture {
            // The panel's rows handle their own clicks; a tap on the ears or a pulse opens the thread they show.
            guard presentation != .expanded else { return }
            if case .pulse(.agent(let thread)) = presentation { return open(thread) }
            if case .agents(let summary) = content { open(summary.lead) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.barWhite)
        .animation(islandSpring, value: content)
        .animation(islandSpring, value: threads.map(\.id))
        .onChange(of: model.pulse) { if let pulse = model.pulse { controller.pulse(pulse.kind) } }
        .onChange(of: content) { controller.update() }
    }

    private func open(_ thread: AgentThread) {
        controller.dismiss()
        model.open(thread)
    }
}

/// A hairline around the part of the island below the bar.
private struct IslandOutline: View {
    let shape: IslandShape
    let fadeIn: CGFloat

    var body: some View {
        let stops: [Gradient.Stop] = [.init(color: .clear, location: 0), .init(color: .clear, location: fadeIn), .init(color: .white.opacity(0.16), location: 1)]
        shape.stroke(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }
}

/// The notch's outline: square top edge flaring outward into the screen edge, rounded bottom corners.
struct IslandShape: Shape {
    var bottomRadius: CGFloat
    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = max(0, min(bottomRadius, rect.height / 2, rect.width / 2))
        let f = min(IslandGeometry.flare, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + f), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        path.addQuadCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The two ears beside the hardware notch. Content hugs the outer ends, like the Dynamic Island's live activities.
private struct EarsRow: View {
    let content: IslandContent
    let notchWidth: CGFloat
    let earWidth: CGFloat
    let height: CGFloat
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            Group {
                switch content {
                case .agents(let summary):
                    HStack(spacing: 7) {
                        ProjectChip(thread: summary.lead)
                        Text(summary.lead.project)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .id(summary.lead.id)
                case .nowPlaying:
                    Artwork(image: artwork, size: 22, radius: 6)
                case .idle:
                    EmptyView()
                }
            }
            .transition(.blurReplace)
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            Group {
                switch content {
                case .agents(let summary):
                    HStack(spacing: 6) {
                        if summary.count > 1 {
                            Text("\(summary.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.barWhite.opacity(0.75))
                                .contentTransition(.numericText(value: Double(summary.count)))
                        }
                        AgentIndicator(status: summary.lead.status, size: 16)
                    }
                case .nowPlaying(let nowPlaying):
                    Equalizer(playing: nowPlaying.playing).frame(width: 14, height: 14)
                case .idle:
                    EmptyView()
                }
            }
            .transition(.blurReplace)
            .padding(.trailing, 13)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: height)
    }
}

/// The line under the notch during a pulse: what happened and to which thread, or the new track.
private struct PulseRow: View {
    let pulse: IslandPulse
    let artwork: NSImage?

    var body: some View {
        HStack(spacing: 11) {
            switch pulse {
            case .agent(let thread):
                AgentIndicator(status: thread.status, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text("\(thread.status.headline) · \(thread.project)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(thread.status.color.opacity(0.9))
                        .lineLimit(1)
                }
            case .track(let nowPlaying):
                Artwork(image: artwork, size: 30, radius: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.title).font(.system(size: 13, weight: .bold)).lineLimit(1)
                    Text(nowPlaying.artist).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.barWhite.opacity(0.65)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 20)
        .padding(.bottom, 4)
    }
}

/// The drop-down: recent threads, then what is playing.
private struct IslandPanelContent: View {
    let model: BarModel
    let threads: [AgentThread]
    let open: (AgentThread) -> Void

    var body: some View {
        VStack(spacing: 4) {
            if !threads.isEmpty {
                // Elapsed times tick only while the panel is open.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 0) {
                        ForEach(threads) { thread in
                            ThreadRow(thread: thread, now: context.date) { open(thread) }
                        }
                    }
                }
            }
            if let nowPlaying = model.nowPlaying {
                NowPlayingCard(nowPlaying: nowPlaying, artwork: model.artwork, control: model.control)
            }
        }
        .padding(.horizontal, 6)
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let now: Date
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            AgentIndicator(status: thread.status, size: 18)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ProjectChip(thread: thread, size: 12)
                    Text("\(thread.project) · \(thread.provider.displayName)")
                        .lineLimit(1)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.barWhite.opacity(0.55))
            }
            Spacer(minLength: 8)
            Text(thread.status == .running ? elapsedText(since: thread.turnStartedAt ?? thread.updatedAt, now: now)
                                           : elapsedText(since: thread.updatedAt, now: now))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(thread.status == .idle ? Color.barWhite.opacity(0.45) : thread.status.color)
        }
        .padding(.horizontal, 6)
        .frame(height: IslandGeometry.rowHeight)
        .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0)) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct NowPlayingCard: View {
    let nowPlaying: NowPlaying
    let artwork: NSImage?
    let control: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Artwork(image: artwork, size: 44, radius: 10)
                .onTapGesture { shell("open -b \(nowPlaying.player.rawValue)") }
            VStack(alignment: .leading, spacing: 2) {
                Marquee(text: nowPlaying.title, font: .system(size: 13, weight: .bold), width: 190)
                Marquee(text: nowPlaying.artist, font: .system(size: 11, weight: .semibold), width: 190)
                    .foregroundStyle(Color.barWhite.opacity(0.65))
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                TransportButton(symbol: "backward.fill") { control("previous track") }
                TransportButton(symbol: nowPlaying.playing ? "pause.fill" : "play.fill") { control("playpause") }
                TransportButton(symbol: "forward.fill") { control("next track") }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: IslandGeometry.cardHeight)
        .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.white.opacity(0.07)) }
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
                Image(systemName: "music.note").font(.system(size: size * 0.5, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// The project's initial on a chip in the provider's colour: coral for Claude, white for Codex.
struct ProjectChip: View {
    let thread: AgentThread
    var size: CGFloat = 18

    var body: some View {
        let (fill, ink): (Color, Color) = switch thread.provider {
        case .claude: (Color(hex: 0xD97757), .white)
        case .codex: (Color(hex: 0xF2F2F7), .black)
        case .other: (Color.white.opacity(0.25), .white)
        }
        Text(thread.project.first.map { String($0).uppercased() } ?? "•")
            .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(fill))
    }
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .running: Color(hex: 0x6FB6FF)
        case .needsInput: Color(hex: 0xFFB340)
        case .done: .barGreen
        case .error: .barRed
        case .idle: .barWhite.opacity(0.4)
        }
    }

    var headline: String {
        switch self {
        case .running: "Working"
        case .needsInput: "Needs you"
        case .done: "Finished"
        case .error: "Failed"
        case .idle: "Idle"
        }
    }
}
