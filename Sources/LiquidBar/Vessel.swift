import AppKit
import LiquidBarCore
import SwiftUI

/// Steps one vessel's fluid on the display's clock and draws it, only while something moves: the display link
/// pauses the moment the simulation rests, so a still bar draws nothing.
@MainActor
final class FluidController: NSObject {
    private var sim: FluidSim
    private var link: CADisplayLink?
    private var last: CFTimeInterval?
    private(set) lazy var view = FerroView()
    #if DEBUG
    /// Slows the fluid down so screen captures, which take ~100ms each, can follow it frame by frame.
    static var slowdown = 1.0
    #else
    static let slowdown = 1.0
    #endif

    init(source: FluidSim.End) {
        sim = FluidSim(source: source)
        super.init()
        // A new desktop picture, or the space's own, changes what the fluid reflects.
        let redraw: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.draw() } }
        NotificationCenter.default.addObserver(forName: Wallpaper.changed, object: nil, queue: .main, using: redraw)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: redraw)
    }

    func resize(_ size: CGSize) {
        guard size.width != sim.width || size.height != sim.height else { return }
        sim.resize(width: size.width, height: size.height)
        wake()
    }

    func gather(_ places: [Gather]) {
        sim.gather(places)
        wake()
    }

    func point(at x: Double?) {
        sim.point(at: x)
        wake()
    }

    func burst(_ id: String) {
        sim.burst(id)
        wake()
    }

    func ripple(_ id: String) {
        sim.ripple(id)
        wake()
    }

    private func wake() {
        guard !sim.resting || link?.isPaused == false else { return draw() }
        if link == nil {
            guard view.window != nil else { return }
            link = view.displayLink(target: self, selector: #selector(tick))
            link?.add(to: .main, forMode: .common)
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        // After a pause the first interval would span the whole rest; take one frame's worth instead.
        let dt = min(1.0 / 30, last.map { link.targetTimestamp - $0 } ?? link.duration)
        last = link.targetTimestamp
        sim.step(dt / Self.slowdown)
        draw()
        if sim.resting {
            link.isPaused = true
            last = nil
        }
    }

    private func draw() {
        guard sim.width > 0 else { return }
        view.draw(sim.frame)
    }

    /// The first frames can arrive before the view is in a window, where there is no display to link to.
    func attached() {
        wake()
    }
}

private struct FluidLayer: NSViewRepresentable {
    let controller: FluidController

    func makeNSView(context: Context) -> FerroView {
        controller.view.onWindow = { [controller] in controller.attached() }
        return controller.view
    }

    func updateNSView(_ view: FerroView, context: Context) {}
}

/// A cue for the fluid that is not a state: a ripple across an item, or a burst of its spikes.
struct FluidKick: Equatable {
    enum Kind { case ripple, burst }
    let id = UUID()
    let item: String
    let kind: Kind
}

extension EnvironmentValues {
    /// Where an item reports its frame in its vessel, so the fluid knows where to gather.
    @Entry var fluidFrame: (String, CGRect) -> Void = { _, _ in }
}

/// A clear glass ampoule with ferrofluid inside. Items sit above the fluid; `places` says where it gathers given
/// where the items are.
struct Vessel<Content: View>: View {
    let source: FluidSim.End
    let height: CGFloat
    let kick: FluidKick?
    let places: ([String: CGRect]) -> [Gather]
    @ViewBuilder let content: Content
    @State private var controller: FluidController
    @State private var frames: [String: CGRect] = [:]

    init(source: FluidSim.End, height: CGFloat, kick: FluidKick?, places: @escaping ([String: CGRect]) -> [Gather], @ViewBuilder content: () -> Content) {
        self.source = source
        self.height = height
        self.kick = kick
        self.places = places
        self.content = content()
        _controller = State(initialValue: FluidController(source: source))
    }

    var body: some View {
        let places = places(frames)
        content
            // Clear glass over a light wallpaper leaves white text faint; a soft shadow keeps it readable.
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
            .environment(\.fluidFrame) { id, frame in frames[id] = frame }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: source == .leading ? .trailing : .leading)
            .frame(height: height)
            .coordinateSpace(.named(VesselSpace.name))
            // The glass sits behind the fluid: in front, it blurred the black into a smudge. The shader draws the front
            // glass's sheen over the fluid instead.
            .background {
                FluidLayer(controller: controller)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { controller.resize($0) }
            }
            .glassEffect(.clear, in: .capsule)
            .onContinuousHover(coordinateSpace: .named(VesselSpace.name)) { phase in
                if case .active(let point) = phase { controller.point(at: point.x) } else { controller.point(at: nil) }
            }
            .onChange(of: places, initial: true) { controller.gather(places) }
            .onChange(of: kick) {
                guard let kick, frames[kick.item] != nil else { return }
                switch kick.kind {
                case .ripple: controller.ripple(kick.item)
                case .burst: controller.burst(kick.item)
                }
            }
    }
}


enum VesselSpace {
    static let name = "vessel"
}

extension View {
    /// Reports this item's frame to its vessel under `id`.
    func fluidItem(_ id: String) -> some View {
        modifier(FluidItem(id: id))
    }
}

private struct FluidItem: ViewModifier {
    let id: String
    @Environment(\.fluidFrame) private var report

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(VesselSpace.name)) } action: { report(id, $0) }
    }
}

extension Color {
    /// Straight sRGB components with an alpha, as the shader takes colours.
    func fluidTint(_ amount: Float = 1) -> SIMD4<Float> {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return .zero }
        return SIMD4(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), amount)
    }
}
