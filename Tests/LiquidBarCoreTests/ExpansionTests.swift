import Foundation
import LiquidBarCore
import Testing

private typealias Inputs = ExpansionInputs<String>
private let t0 = Date(timeIntervalSince1970: 1000)
private func at(_ seconds: Double) -> Date { t0 + seconds }

@Test func hoverExpandsOnlyAfterIntent() {
    let inputs = Inputs(inside: .init("volume", t0))
    #expect(inputs.owner(now: at(0.05), current: nil).id == nil)
    #expect(inputs.owner(now: at(0.05), current: nil).recheck == at(0.09))
    #expect(inputs.owner(now: at(0.1), current: nil).id == "volume")
}

@Test func sweepingAcrossPillsExpandsOneAtATime() {
    // The pointer rested on volume, then moved to battery: battery takes the slot once intent passes,
    // volume collapses at that moment instead of lingering beside it.
    let inputs = Inputs(inside: .init("battery", at(1)), left: .init("volume", at(1)))
    #expect(inputs.owner(now: at(1.05), current: "volume").id == "volume")
    #expect(inputs.owner(now: at(1.1), current: "volume").id == "battery")
}

@Test func leavingLingersThenCollapses() {
    let inputs = Inputs(left: .init("wifi", at(2)))
    #expect(inputs.owner(now: at(2.5), current: "wifi").id == "wifi")
    #expect(inputs.owner(now: at(2.5), current: "wifi").recheck == at(2.9))
    #expect(inputs.owner(now: at(3), current: "wifi").id == nil)
    // A pill that was never expanded does not linger.
    #expect(inputs.owner(now: at(2.5), current: nil).id == nil)
}

@Test func reenteringTheExpandedPillSkipsIntent() {
    let inputs = Inputs(inside: .init("clock", at(3.85)), left: .init("clock", at(3)))
    #expect(inputs.owner(now: at(3.9), current: "clock").id == "clock")
    #expect(inputs.owner(now: at(3.9), current: "clock").recheck == nil)
}

@Test func pulseWinsThenHoverReturns() {
    let inputs = Inputs(inside: .init("battery", t0), pulse: .init("volume", at(2.2)))
    #expect(inputs.owner(now: at(1), current: "battery").id == "volume")
    #expect(inputs.owner(now: at(1), current: "battery").recheck == at(2.2))
    #expect(inputs.owner(now: at(2.3), current: "volume").id == "battery")
    #expect(Inputs(pulse: .init("volume", at(2.2))).owner(now: at(2.3), current: "volume").id == nil)
}
