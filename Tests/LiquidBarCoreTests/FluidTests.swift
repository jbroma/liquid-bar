import LiquidBarCore
import Testing

private func settle(_ sim: inout FluidSim, seconds: Double = 4) {
    for _ in 0..<Int(seconds * 120) { sim.step(1.0 / 120) }
}

private func poured(source: FluidSim.End = .trailing) -> FluidSim {
    var sim = FluidSim(source: source)
    sim.resize(width: 600, height: 34)
    settle(&sim)
    return sim
}

@Test func pouringFromTheNotchFillsTheVesselThenRests() {
    var sim = FluidSim(source: .trailing)
    sim.resize(width: 600, height: 34)
    sim.step(0.2)
    #expect(!sim.resting)
    #expect(sim.frame.filmTo == 600)
    #expect(sim.frame.filmFrom > 300)
    settle(&sim)
    #expect(sim.resting)
    #expect(sim.frame.filmFrom == 0)
    #expect(sim.frame.mounds.isEmpty && sim.frame.spikes.isEmpty)
}

@Test func fluidGathersUnderAnItemAndDrainsBack() {
    var sim = poured()
    sim.gather([Gather(id: "volume", minX: 100, maxX: 140, height: 0.5)])
    settle(&sim)
    #expect(sim.resting)
    let mound = try! #require(sim.frame.mounds.first)
    #expect(sim.frame.mounds.count == 1)
    #expect(mound.x == 120)
    #expect(mound.z == 15)  // half of the 30pt inside a 34pt vessel with 2pt walls
    sim.gather([])
    settle(&sim)
    #expect(sim.resting)
    #expect(sim.frame.mounds.isEmpty)
}

@Test func theDropletStretchesBetweenWorkspacesThenSettlesAsOne() {
    var sim = poured()
    sim.gather([Gather(id: "droplet", minX: 40, maxX: 70, height: 0.7, flows: true)])
    settle(&sim)
    sim.gather([Gather(id: "droplet", minX: 240, maxX: 270, height: 0.7, flows: true)])
    sim.step(0.06)
    let stretched = sim.frame.mounds.map(\.x)
    #expect(stretched.count == 2)
    #expect(stretched[0] > stretched[1])  // the front leads, the back trails
    settle(&sim)
    #expect(sim.frame.mounds.map(\.x) == [255])
}

@Test func spikesReachForThePointer() {
    var sim = poured()
    sim.point(at: 150)
    sim.gather([Gather(id: "battery", minX: 100, maxX: 160, height: 0.4, spikes: 1)])
    settle(&sim)
    let tallest = try! #require(sim.frame.spikes.max { $0.y < $1.y })
    #expect(tallest.x > 140)
    #expect(sim.frame.spikes.allSatisfy { $0.y + 12 <= 30 })  // spikes stay inside the glass
    sim.point(at: nil)
    sim.gather([])
    settle(&sim)
    #expect(sim.frame.spikes.isEmpty)
}

@Test func ripplesFadeAndTheFluidRestsAgain() {
    var sim = poured()
    sim.ripple(at: 300)
    #expect(!sim.resting)
    #expect(sim.frame.ripples.count == 1)
    settle(&sim, seconds: FluidSim.rippleLife + 0.1)
    #expect(sim.resting)
}
