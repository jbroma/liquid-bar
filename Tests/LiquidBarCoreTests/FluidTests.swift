import LiquidBarCore
import Testing

private func settle(_ sim: inout FluidSim, seconds: Double = 4) {
    for _ in 0..<Int(seconds * 120) { sim.step(1.0 / 120) }
}

/// A 600 x 34 vessel whose fluid has already come out of the notch into a droplet at 40...70.
private func vessel() -> FluidSim {
    var sim = FluidSim(source: .trailing)
    sim.resize(width: 600, height: 34)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true)])
    settle(&sim)
    return sim
}

@Test func theFirstBeadFlowsOutOfTheNotchEndThenRests() {
    var sim = FluidSim(source: .trailing)
    sim.resize(width: 600, height: 34)
    #expect(sim.frame.beads.isEmpty)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true)])
    sim.step(0.05)
    #expect(sim.frame.beads.allSatisfy { $0.x > 400 })  // still near the notch at the right end
    settle(&sim)
    #expect(sim.resting)
    #expect(sim.frame.beads == [SIMD4(55, 17, 15, 13.5)])  // wraps the item, 1.5pt clear of 2pt glass walls
}

@Test func aBeadWrapsTheHoveredItemAndShrinksAwayAfter() {
    var sim = vessel()
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true), Gather(id: "volume", minX: 400, maxX: 460)])
    settle(&sim)
    #expect(sim.frame.beads.map(\.x) == [55, 430])
    #expect(sim.frame.beads[1].z == 30)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true)])
    settle(&sim)
    #expect(sim.resting)
    #expect(sim.frame.beads.map(\.x) == [55])
}

@Test func theDropletStretchesNecksAndReformsAtTheNewWorkspace() {
    var sim = vessel()
    sim.gather([Gather(id: "droplet", minX: 240, maxX: 270, flows: true)])
    sim.step(0.04)
    // Front, neck and back: the front leads, the neck sits between, the back trails.
    let stretched = sim.frame.beads
    #expect(stretched.count == 3)
    #expect(stretched[0].x > stretched[1].x && stretched[1].x > stretched[2].x)
    #expect(stretched[1].w < stretched[0].w / 2)
    settle(&sim)
    #expect(sim.frame.beads.map(\.x) == [255])
}

@Test func spikesLeanTowardThePointerAndSettleToAClosedShape() {
    var sim = vessel()
    sim.point(at: 460)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true), Gather(id: "wifi", minX: 400, maxX: 450, spikes: 0.5)])
    settle(&sim)
    let spikes = sim.frame.spikes
    #expect(!spikes.isEmpty)
    #expect(spikes.map(\.z).reduce(0, +) / Float(spikes.count) > 425)  // they lean toward the pointer on the right
    sim.point(at: nil)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true)])
    settle(&sim)
    #expect(sim.frame.spikes.isEmpty)
}

@Test func aKickForABeadThatIsStillGrowingIsNotLost() {
    var sim = vessel()
    sim.burst("battery")
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true), Gather(id: "battery", minX: 500, maxX: 560)])
    sim.step(0.1)
    #expect(!sim.frame.spikes.isEmpty)
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, flows: true)])
    settle(&sim)
    #expect(sim.resting)
}

@Test func aShrinkingBeadFollowsItsItemAsItCollapses() {
    var sim = vessel()
    let droplet = Gather(id: "droplet", minX: 40, maxX: 70, flows: true)
    sim.gather([droplet, Gather(id: "nowPlaying", minX: 300, maxX: 500)])
    settle(&sim)
    // The detail folds away: the item is narrow again at its right end, and the bead goes with it while it shrinks.
    sim.gather([droplet, Gather(id: "nowPlaying", minX: 460, maxX: 500, present: false)])
    for _ in 0..<24 { sim.step(1.0 / 120) }
    let bead = try! #require(sim.frame.beads.first { $0.x > 100 })
    #expect(bead.x > 420)
    #expect(bead.z < 40)
    settle(&sim)
    #expect(sim.frame.beads.count == 1)
}
