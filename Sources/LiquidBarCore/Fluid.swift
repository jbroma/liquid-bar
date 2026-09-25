import Foundation

/// A damped spring toward `target`, stepped by the caller's clock. `response` is the period in seconds; `damping`
/// below 1 overshoots.
public struct Spring: Equatable, Sendable {
    public var value: Double
    public var velocity: Double = 0
    public var target: Double
    public var response: Double
    public var damping: Double

    public init(_ value: Double, response: Double = 0.4, damping: Double = 0.8) {
        self.value = value
        self.target = value
        self.response = response
        self.damping = damping
    }

    public var resting: Bool { value == target && velocity == 0 }

    public mutating func step(_ dt: Double) {
        guard !resting else { return }
        let stiffness = pow(2 * .pi / response, 2)
        let friction = 2 * damping * stiffness.squareRoot()
        // Semi-implicit Euler in small steps stays stable for stiff springs at any frame rate.
        let steps = max(1, Int((dt / (1.0 / 480)).rounded(.up)))
        let h = dt / Double(steps)
        for _ in 0..<steps {
            velocity += (-stiffness * (value - target) - friction * velocity) * h
            value += velocity * h
        }
        // Close enough to be invisible: stop, so the display link can stop too.
        if abs(value - target) < 0.005, abs(velocity) < 0.05 {
            value = target
            velocity = 0
        }
    }
}

/// One place where fluid gathers: under a hovered or pulsing item, or under the focused workspace.
public struct Gather: Equatable, Sendable {
    public var id: String
    public var minX: Double
    public var maxX: Double
    /// Height as a fraction of the vessel's inner height.
    public var height: Double
    /// Spike strength, 0...1.
    public var spikes: Double
    /// Rim colour: straight rgb and how strongly it shows.
    public var tint: SIMD4<Float>
    /// Moving to a new place flows like a droplet, stretching and necking, instead of draining and refilling.
    public var flows: Bool

    public init(id: String, minX: Double, maxX: Double, height: Double, spikes: Double = 0, tint: SIMD4<Float> = .zero, flows: Bool = false) {
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.height = height
        self.spikes = spikes
        self.tint = tint
        self.flows = flows
    }
}

/// What the renderer draws for one frame, in the shader's units (points, heights above the vessel's inner bottom).
public struct FluidFrame: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var inset: Double
    public var film: Double
    public var filmFrom: Double
    public var filmTo: Double
    /// Center, half width, height, corner radius.
    public var mounds: [SIMD4<Float>] = []
    public var tints: [SIMD4<Float>] = []
    /// x, height, half width, unused.
    public var spikes: [SIMD4<Float>] = []
    /// Origin, amplitude, wavelength, distance travelled.
    public var ripples: [SIMD4<Float>] = []
}

/// Ferrofluid in one glass vessel: a thin film along the bottom, poured in from the notch end at launch, gathering
/// into mounds where it is called and raising spikes toward the pointer. Pure state stepped by a clock, so it can
/// rest completely: `resting` is true once nothing moves and nothing needs drawing.
public struct FluidSim: Equatable, Sendable {
    public enum End: Equatable, Sendable { case leading, trailing }

    struct Mound: Equatable, Sendable {
        var center: Spring
        /// Follows the center more lazily; while the two are apart the fluid stretches between them.
        var trail: Spring
        var halfWidth: Spring
        var height: Spring
        var spikes: Spring
        var tint: SIMD4<Float>
        var flows: Bool
    }

    struct Ripple: Equatable, Sendable {
        var origin: Double
        var age: Double
    }

    public var width: Double = 0
    public var height: Double = 0
    /// The vessel end next to the notch, where the fluid pours in from.
    public var source: End
    public var inset = 2.0
    public var film = 4.0
    var reach = Spring(0, response: 1.1, damping: 0.9)
    var mounds: [String: Mound] = [:]
    var magnet = Spring(0, response: 0.25, damping: 0.9)
    var magnetized = false
    var ripples: [Ripple] = []

    public init(source: End) {
        self.source = source
    }

    public static let rippleLife = 1.4

    public var resting: Bool {
        reach.resting && magnet.resting && ripples.isEmpty
            && mounds.values.allSatisfy { [$0.center, $0.trail, $0.halfWidth, $0.height, $0.spikes].allSatisfy(\.resting) }
    }

    /// Sizes the vessel. The first size starts the pour.
    public mutating func resize(width: Double, height: Double) {
        self.width = width
        self.height = height
        reach.target = 1
    }

    /// Where fluid should gather now. Places no longer listed drain back into the film where they stand.
    public mutating func gather(_ places: [Gather]) {
        for place in places {
            let center = (place.minX + place.maxX) / 2, half = (place.maxX - place.minX) / 2
            var mound = mounds[place.id] ?? Mound(
                center: Spring(center, response: 0.36, damping: 0.62),
                trail: Spring(center, response: 0.62, damping: 0.95),
                halfWidth: Spring(half, response: 0.4, damping: 0.75),
                height: Spring(0, response: 0.42, damping: 0.68),
                spikes: Spring(0, response: 0.3, damping: 0.55),
                tint: place.tint, flows: place.flows)
            if mound.height.value < 0.01 {
                // Rising out of the film: grow in place instead of sliding in from where it last drained.
                (mound.center.value, mound.trail.value, mound.halfWidth.value) = (center, center, half)
            }
            mound.center.target = center
            mound.trail.target = center
            mound.halfWidth.target = half
            mound.height.target = place.height
            mound.spikes.target = place.spikes
            mound.tint = place.tint
            mound.flows = place.flows
            mounds[place.id] = mound
        }
        let listed = Set(places.map(\.id))
        for id in mounds.keys where !listed.contains(id) {
            mounds[id]!.height.target = 0
            mounds[id]!.spikes.target = 0
        }
    }

    /// The pointer's x, the magnet the spikes reach for; nil once it leaves.
    public mutating func point(at x: Double?) {
        magnetized = x != nil
        if let x {
            if magnet.resting && magnet.value == 0 { magnet.value = x }
            magnet.target = x
        }
    }

    /// A kick to one mound's spikes, like a charger plugging in.
    public mutating func burst(_ id: String) {
        mounds[id]?.spikes.velocity += 14
    }

    public mutating func ripple(at x: Double) {
        ripples.append(Ripple(origin: x, age: 0))
    }

    public mutating func step(_ dt: Double) {
        reach.step(dt)
        magnet.step(dt)
        for id in Array(mounds.keys) {
            mounds[id]!.center.step(dt)
            mounds[id]!.trail.step(dt)
            mounds[id]!.halfWidth.step(dt)
            mounds[id]!.height.step(dt)
            mounds[id]!.spikes.step(dt)
            let mound = mounds[id]!
            if mound.height.resting, mound.height.value == 0, mound.spikes.resting { mounds[id] = nil }
        }
        ripples = ripples.map { Ripple(origin: $0.origin, age: $0.age + dt) }.filter { $0.age < Self.rippleLife }
    }

    public var frame: FluidFrame {
        let inner = max(0, height - 2 * inset)
        let reachX = reach.value * width
        let filmFrom = source == .leading ? 0 : width - reachX
        let filmTo = source == .leading ? reachX : width
        var frame = FluidFrame(width: width, height: height, inset: inset, film: film, filmFrom: filmFrom, filmTo: filmTo)
        // Fluid can only gather where the pour has reached.
        func poured(_ x: Double) -> Double {
            let fromSource = source == .leading ? x : width - x
            return min(1, max(0, (reachX - fromSource) / 40))
        }
        func add(_ center: Double, _ half: Double, _ height: Double, _ tint: SIMD4<Float>) {
            guard height > 0.2 else { return }
            let corner = min(height * 0.85, half)
            frame.mounds.append(SIMD4(Float(center), Float(half), Float(height), Float(corner)))
            frame.tints.append(tint)
        }
        // The pour's leading edge carries a bead of fluid that shrinks as it spreads.
        if reach.value > 0, reach.value < 0.995 {
            let front = source == .leading ? reachX : width - reachX
            add(front, 9, inner * 0.4 * (1 - reach.value).squareRoot(), .zero)
        }
        for id in mounds.keys.sorted() {
            let mound = mounds[id]!
            let lead = mound.center.value, trail = mound.trail.value
            let stretch = abs(lead - trail)
            let half = max(0, mound.halfWidth.value)
            let h = max(0, mound.height.value) * inner * poured(lead)
            // Stretched out, the droplet thins at the front and drains at the back; the neck between them is the
            // film's smooth join, which thins and snaps as they part.
            add(lead, half * (1 - 0.15 * min(1, stretch / 100)), h * (1 - 0.3 * min(1, stretch / 120)), mound.tint)
            if mound.flows, stretch > 0.5 {
                add(trail, half * 0.75, h * max(0, 1 - stretch / 150), mound.tint)
            }
            let strength = mound.spikes.value
            guard strength > 0.01, half > 4 else { continue }
            let count = min(9, max(3, Int(half * 2 / 9)))
            let span = half * 0.8
            let pull = magnetized && abs(magnet.value - lead) < half + 12 ? magnet.value : lead
            for i in 0..<count {
                let x = lead - span + 2 * span * Double(i) / Double(count - 1)
                let near = exp(-pow((x - pull) / max(8, half * 0.55), 2))
                // Uneven like real peaks, but the same unevenness every time.
                let jitter = 0.8 + 0.2 * abs(sin(Double(i) * 12.9898 + half))
                let room = max(0, inner - h - 1.5)
                let spike = min(room, strength * inner * 0.42 * near * jitter)
                if spike > 0.2 { frame.spikes.append(SIMD4(Float(x), Float(spike), 4.2, 0)) }
            }
        }
        for ripple in ripples {
            let fade = exp(-ripple.age * 2.4)
            frame.ripples.append(SIMD4(Float(ripple.origin), Float(2.4 * fade), 14, Float(ripple.age * 55)))
        }
        return frame
    }
}
