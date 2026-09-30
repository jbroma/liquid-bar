import Foundation
import LiquidBarCore
import Testing

private typealias Inputs = ExpansionInputs<String>
private let t0 = Date(timeIntervalSince1970: 1000)
private func at(_ seconds: Double) -> Date { t0 + seconds }

@Test func hoverExpandsOnlyAfterIntent() {
    let inputs = Inputs(inside: .init("volume", t0))
    #expect(inputs.owner(now: at(0.02), current: nil).id == nil)
    #expect(inputs.owner(now: at(0.02), current: nil).recheck == at(0.04))
    #expect(inputs.owner(now: at(0.05), current: nil).id == "volume")
}

@Test func slidingToAnotherPillWhileOneIsOpenSwitchesAtOnce() {
    // Like the native menu bar: volume's dropdown is open and the pointer moves to battery, which opens with no
    // intent delay while volume closes.
    let inputs = Inputs(inside: .init("battery", at(1)), left: .init("volume", at(1)))
    #expect(inputs.owner(now: at(1), current: "volume") == ("battery", at(1.15)))
}

@Test func leavingLingersThenCollapses() {
    let inputs = Inputs(left: .init("wifi", at(2)))
    #expect(inputs.owner(now: at(2.1), current: "wifi").id == "wifi")
    #expect(inputs.owner(now: at(2.1), current: "wifi").recheck == at(2.15))
    #expect(inputs.owner(now: at(2.2), current: "wifi").id == nil)
    // A pill that was never expanded does not linger.
    #expect(inputs.owner(now: at(2.3), current: nil).id == nil)
}

@Test func reenteringTheExpandedPillSkipsIntent() {
    let inputs = Inputs(inside: .init("clock", at(3.85)), left: .init("clock", at(3)))
    #expect(inputs.owner(now: at(3.9), current: "clock").id == "clock")
    #expect(inputs.owner(now: at(3.9), current: "clock").recheck == nil)
}

@Test func hoverWinsOverPulse() {
    // The volume changes while the pointer rests on battery: battery stays open, and after the pointer leaves it
    // lingers and closes without volume opening.
    let resting = Inputs(inside: .init("battery", t0), pulse: .init("volume", at(2.2)))
    #expect(resting.owner(now: at(1), current: "battery").id == "battery")
    let leaving = Inputs(pulse: .init("volume", at(2.2)), left: .init("battery", at(1.5)))
    #expect(leaving.owner(now: at(1.6), current: "battery") == ("battery", at(1.65)))
    #expect(leaving.owner(now: at(2.1), current: "battery").id == nil)
    // The pointer arrives on battery during volume's pulse: the open dropdown moves to battery at once.
    let arriving = Inputs(inside: .init("battery", at(1)), pulse: .init("volume", at(2.2)))
    #expect(arriving.owner(now: at(1), current: "volume") == ("battery", nil))
}

@Test func pulseOpensWhileNothingIsHovered() {
    let inputs = Inputs(pulse: .init("volume", at(2.2)))
    #expect(inputs.owner(now: at(1), current: nil) == ("volume", at(2.2)))
    #expect(inputs.owner(now: at(2.3), current: "volume").id == nil)
}

@Test func pulsesThatAreNotNewsAreIgnored() {
    var quiet = Inputs(quietUntil: at(2))
    #expect(quiet.startPulse("volume", now: at(1), current: nil) == false)
    #expect(quiet.startPulse("volume", now: at(2), current: nil) == true)
    #expect(quiet.pulse == .init("volume", at(2) + Inputs.pulseLength))
    // Dragging the volume slider: the pointer is in volume's open dropdown.
    var dragging = Inputs(holding: true)
    #expect(dragging.startPulse("volume", now: t0, current: "volume") == false)
    #expect(dragging.startPulse("wifi", now: t0, current: "volume") == true)
    var hovering = Inputs(inside: .init("volume", t0))
    #expect(hovering.startPulse("volume", now: at(1), current: "volume") == false)
    #expect(hovering.pulse == nil)
}

@Test func pulsesAreQuietForFiveSecondsAfterWake() {
    var inputs = Inputs(quietUntil: at(2))
    inputs.woke(at: at(100))
    #expect(inputs.startPulse("wifi", now: at(104.9), current: nil) == false)
    #expect(inputs.startPulse("wifi", now: at(105), current: nil) == true)
    // A wake right after launch keeps the longer of the two quiet times.
    var launching = Inputs(quietUntil: at(10))
    launching.woke(at: at(1))
    #expect(launching.quietUntil == at(10))
}

@Test func aChangeShowsInlineOnlyWhenItIsNews() {
    var inputs = Inputs(quietUntil: at(2))
    #expect(inputs.startInline("nowPlaying", now: at(1), current: nil) == false)
    #expect(inputs.startInline("nowPlaying", now: at(2), current: nil) == true)
    #expect(inputs.inline == .init("nowPlaying", at(5)))
    // A second track while the first shows restarts the time.
    #expect(inputs.startInline("nowPlaying", now: at(4), current: nil) == true)
    #expect(inputs.inline == .init("nowPlaying", at(7)))
    // The open dropdown already shows the change, whether the pointer is on the pill or it lingers after leaving.
    var open = Inputs(left: .init("nowPlaying", at(1)))
    #expect(open.startInline("nowPlaying", now: at(1.2), current: "nowPlaying") == false)
    var hovering = Inputs(inside: .init("nowPlaying", t0))
    #expect(hovering.startInline("nowPlaying", now: at(1), current: nil) == false)
    #expect(hovering.inline == nil)
}

@Test func anInlineChangeEndsAfterItsTimeUnlessThePointerIsOnIt() {
    var inputs = Inputs(inline: .init("nowPlaying", at(3)))
    #expect(inputs.inlined(now: at(1), current: nil) == ("nowPlaying", at(3)))
    #expect(inputs.inlined(now: at(3), current: nil) == (nil, nil))
    #expect(inputs.inline == nil)
    // The pointer came to the pill and opened its dropdown: it stays wide until the dropdown closes.
    var held = Inputs(inside: .init("nowPlaying", at(2)), inline: .init("nowPlaying", at(3)))
    #expect(held.inlined(now: at(4), current: "nowPlaying") == ("nowPlaying", nil))
    held.inside = nil
    #expect(held.inlined(now: at(5), current: "nowPlaying") == ("nowPlaying", nil))
    #expect(held.inlined(now: at(5.5), current: nil) == (nil, nil))
    // Hovering it again later does not bring the change back.
    held.inside = .init("nowPlaying", at(6))
    #expect(held.inlined(now: at(6), current: nil) == (nil, nil))
}

@Test func theOpenDropdownHoldsItsItem() {
    // The pointer crossed from the pill into its dropdown: the pill's exit and the dropdown's entry arrive in either
    // order, and neither the linger nor a pulse elsewhere closes it.
    let crossed = Inputs(left: .init("battery", at(5)), holding: true)
    #expect(crossed.owner(now: at(9), current: "battery") == ("battery", nil))
    let pulsed = Inputs(pulse: .init("volume", at(7)), holding: true)
    #expect(pulsed.owner(now: at(6), current: "battery").id == "battery")
    // Holding with nothing open opens nothing.
    #expect(Inputs(holding: true).owner(now: at(6), current: nil).id == nil)
}

@Test func pointerOutsideDropsMissedClaimsAndTheLingerRunsFromThere() {
    var inputs = Inputs(inside: .init("volume", at(1)), holding: true)
    #expect(inputs.pointer(overPill: false, overDropdown: false, now: at(2), current: "volume") == true)
    #expect(inputs.owner(now: at(2.1), current: "volume").id == "volume")
    #expect(inputs.owner(now: at(2.15), current: "volume").id == nil)
}

@Test func pointerInTheGapAboveTheDropdownHolds() {
    var inputs = Inputs(left: .init("volume", at(1)))
    #expect(inputs.pointer(overPill: false, overDropdown: true, now: at(1.1), current: "volume") == true)
    #expect(inputs.owner(now: at(5), current: "volume").id == "volume")
}

@Test func pointerAgreeingWithTheClaimsChangesNothing() {
    var inputs = Inputs(inside: .init("volume", at(1)))
    #expect(inputs.pointer(overPill: true, overDropdown: false, now: at(2), current: "volume") == false)
    #expect(inputs.left == nil)
}
