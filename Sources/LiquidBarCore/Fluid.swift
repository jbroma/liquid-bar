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

/// Where a bead of fluid should sit: around the focused workspace, or around the hovered or pulsing item.
public struct Gather: Equatable, Sendable {
    public var id: String
    public var minX: Double
    public var maxX: Double
    /// Spike strength, 0...1.
    public var spikes: Double
    /// Rim colour: straight rgb and how strongly it shows.
    public var tint: SIMD4<Float>
    /// Moving to a new place flows like a droplet, stretching and necking, instead of shrinking away and regrowing.
    public var flows: Bool
    /// False for an item without a bead: a bead still shrinking away keeps hugging it as it collapses.
    public var present: Bool

    public init(id: String, minX: Double, maxX: Double, spikes: Double = 0, tint: SIMD4<Float> = .zero, flows: Bool = false,
                present: Bool = true) {
        self.present = present
        self.id = id
        self.minX = minX
        self.maxX = maxX
        self.spikes = spikes
        self.tint = tint
        self.flows = flows
    }
}

/// What the renderer draws for one frame, in points with y down from the vessel's top.
public struct FluidFrame: Equatable, Sendable {
    public var width: Double
    public var height: Double
    public var inset: Double
    /// Capsules: center x, center y, half width, half height.
    public var beads: [SIMD4<Float>] = []
    public var tints: [SIMD4<Float>] = []
    /// Tapered spikes: base x, base y, tip x, tip y.
    public var spikes: [SIMD4<Float>] = []
}

/// Ferrofluid in one glass vessel: free beads that wrap the items they belong to, flow between places, and spike
/// toward the pointer or on a pulse. Pure state stepped by a clock, so it can rest completely: `resting` is true once
/// nothing moves.
public struct FluidSim: Sendable {
    public enum End: Equatable, Sendable { case leading, trailing }

    struct Bead: Equatable, Sendable {
        var center: Spring
        /// Follows the center more lazily; while the two are apart the bead stretches, necks and splits between them.
        var trail: Spring
        var halfWidth: Spring
        /// 0 when shrunk away, 1 at full size.
        var size: Spring
        var spikes: Spring
        /// A jiggle, kicked by a track change.
        var wobble: Spring
        var tint: SIMD4<Float>
        var flows: Bool

        var springs: [Spring] { [center, trail, halfWidth, size, spikes, wobble] }
    }

    public var width: Double = 0
    public var height: Double = 0
    /// The vessel end next to the notch, where the fluid comes from at launch.
    public var source: End
    public var inset = 2.0
    /// Air between a bead and the glass, top and bottom.
    public var clearance = 1.5
    var beads: [String: Bead] = [:]
    var magnet: Double?
    var poured = false
    /// Kicks for beads that do not exist yet: a pulse and its kick arrive together, the bead a moment later.
    var pendingKicks: [String: (spikes: Double, wobble: Double)] = [:]

    public init(source: End) {
        self.source = source
    }

    public var resting: Bool {
        beads.values.allSatisfy { $0.springs.allSatisfy(\.resting) }
    }

    public mutating func resize(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Where beads should sit now. Beads not present shrink away around their item, or where they stand once the
    /// item is gone.
    public mutating func gather(_ all: [Gather]) {
        guard width > 0 else { return }
        let places = all.filter(\.present)
        // The first beads flow out of the notch end, the reservoir, instead of appearing in place.
        let pour = !poured && !places.isEmpty
        if pour { poured = true }
        let spout = source == .leading ? 0.0 : width
        for place in all where !place.present && beads[place.id] != nil {
            // A folding item snaps narrow at once; the bead closes in on it quickly while it drains.
            let center = (place.minX + place.maxX) / 2
            for path in [\Bead.center, \.trail] as [WritableKeyPath<Bead, Spring>] {
                beads[place.id]![keyPath: path].target = center
                beads[place.id]![keyPath: path].response = 0.2
                beads[place.id]![keyPath: path].damping = 1
            }
            beads[place.id]!.halfWidth.target = (place.maxX - place.minX) / 2
            beads[place.id]!.halfWidth.response = 0.2
            beads[place.id]!.halfWidth.damping = 1
        }
        for place in places {
            let center = (place.minX + place.maxX) / 2, half = (place.maxX - place.minX) / 2
            var bead = beads[place.id] ?? Bead(
                center: Spring(center),
                trail: Spring(center),
                halfWidth: Spring(half),
                size: Spring(0, response: 0.4, damping: 0.62),
                spikes: Spring(0, response: 0.3, damping: 0.55),
                wobble: Spring(0, response: 0.26, damping: 0.28),
                tint: place.tint, flows: place.flows)
            if pour {
                (bead.center.value, bead.trail.value, bead.size.value) = (spout, spout, 0.6)
            } else if bead.size.value < 0.05 {
                // Growing back from nothing: grow in place instead of sliding in from where it vanished.
                (bead.center.value, bead.trail.value, bead.halfWidth.value) = (center, center, half)
            }
            if let kick = pendingKicks.removeValue(forKey: place.id) {
                bead.spikes.velocity += kick.spikes
                bead.wobble.velocity += kick.wobble
            }
            bead.center.target = center
            bead.trail.target = center
            bead.halfWidth.target = half
            // A bead around an item moves with the bar's own layout spring, so it keeps hugging the item while the
            // item grows; a droplet overshoots like the liquid it is.
            (bead.center.response, bead.center.damping) = (0.38, place.flows ? 0.64 : 0.8)
            (bead.trail.response, bead.trail.damping) = (0.62, 0.9)
            (bead.halfWidth.response, bead.halfWidth.damping) = (0.38, 0.8)
            bead.size.target = 1
            (bead.size.response, bead.size.damping) = (0.4, 0.62)
            bead.spikes.target = place.spikes
            bead.tint = place.tint
            bead.flows = place.flows || pour
            beads[place.id] = bead
        }
        let listed = Set(places.map(\.id))
        for id in beads.keys where !listed.contains(id) {
            // Grows with a little pop, but drains without overshooting through nothing.
            (beads[id]!.size.response, beads[id]!.size.damping) = (0.3, 1)
            beads[id]!.size.target = 0
            beads[id]!.spikes.target = 0
        }
    }

    /// The pointer's x, the magnet the spikes reach for; nil once it leaves.
    public mutating func point(at x: Double?) {
        magnet = x
    }

    /// A kick to one bead's spikes, like a charger plugging in.
    public mutating func burst(_ id: String) {
        kick(id, spikes: 12, wobble: 0)
    }

    /// A jiggle through one bead, like a new track starting.
    public mutating func ripple(_ id: String) {
        kick(id, spikes: 0, wobble: 9)
    }

    private mutating func kick(_ id: String, spikes: Double, wobble: Double) {
        guard beads[id] != nil else { return pendingKicks[id] = (spikes, wobble) }
        beads[id]!.spikes.velocity += spikes
        beads[id]!.wobble.velocity += wobble
    }

    public mutating func step(_ dt: Double) {
        for id in Array(beads.keys) {
            var bead = beads[id]!
            bead.center.step(dt)
            bead.trail.step(dt)
            bead.halfWidth.step(dt)
            bead.size.step(dt)
            bead.spikes.step(dt)
            bead.wobble.step(dt)
            beads[id] = bead.size.resting && bead.size.value == 0 && bead.spikes.resting ? nil : bead
        }
    }

    public var frame: FluidFrame {
        var frame = FluidFrame(width: width, height: height, inset: inset)
        let cy = height / 2
        let fullHalfHeight = max(0, height / 2 - inset - clearance)
        for id in beads.keys.sorted() {
            let bead = beads[id]!
            let size = max(0, bead.size.value)
            guard size > 0.01 else { continue }
            let lead = bead.center.value, trail = bead.trail.value
            let stretch = bead.flows ? abs(lead - trail) : 0
            let squash = bead.wobble.value * 0.08
            // Shrinking, it rounds up into a ball before it vanishes rather than thinning into a sliver.
            let halfHeight = fullHalfHeight * min(1, size).squareRoot() * (1 + squash)
            let halfWidth = max(halfHeight, max(0, bead.halfWidth.value) * size * (1 - squash))
            // Stretched out, the front thins and the back drains; the smooth union between them is the neck, which
            // thins and snaps as they part and closes again as the back catches up.
            let thin = min(1, stretch / 160)
            let front = SIMD4(Float(lead), Float(cy), Float(halfWidth * (1 - 0.15 * thin)), Float(halfHeight * (1 - 0.2 * thin)))
            frame.beads.append(front)
            frame.tints.append(bead.tint)
            if stretch > 0.5 {
                // The neck: a thread between front and back that thins as they part and snaps past 90pt.
                let neck = halfHeight * 0.55 * max(0, 1 - stretch / 90)
                if neck > 2 {
                    frame.beads.append(SIMD4(Float((lead + trail) / 2), Float(cy), Float(stretch / 2 + neck), Float(neck)))
                    frame.tints.append(bead.tint)
                }
                let drain = max(0, 1 - stretch / 240)
                frame.beads.append(SIMD4(Float(trail), Float(cy), Float(max(halfHeight, halfWidth * 0.7) * drain), Float(halfHeight * drain)))
                frame.tints.append(bead.tint)
            }
            let strength = bead.spikes.value
            guard strength > 0.02 else { continue }
            // Spikes stand out of the rounded ends, where the glass leaves them room: more on the end nearer the
            // pointer, evenly on a pulse.
            let lean = magnet.flatMap { abs($0 - lead) < Double(front.z) + 20 ? max(-1, min(1, ($0 - lead) / Double(front.z))) : nil }
            let r = Double(front.w), straight = max(0, Double(front.z) - r)
            for (index, degrees) in [-56.0, -28, 0, 28, 56, 124, 152, 180, 208, 236].enumerated() {
                let a = degrees * .pi / 180
                let (nx, ny) = (cos(a), sin(a))
                let x = lead + (nx > 0 ? straight : -straight) + r * nx, y = cy + r * ny
                let weight = lean.map { max(0, nx * $0) } ?? 1
                let jitter = 0.7 + 0.3 * abs(sin(Double(index) * 12.9898 + Double(id.count)))
                let length = strength * 9 * weight * jitter * abs(nx).squareRoot()
                guard length > 0.6 else { continue }
                frame.spikes.append(SIMD4(Float(x - nx * 2), Float(y - ny * 2), Float(x + nx * length), Float(y + ny * length)))
            }
        }
        return frame
    }
}
