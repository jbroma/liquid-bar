import LiquidBarCore
import Testing

@Test func networksGroupKnownFirstStrongestFirst() {
    let scan = [
        WiFiNetwork(ssid: "Cafe", rssi: -72, secured: false, known: false),
        WiFiNetwork(ssid: "Home", rssi: -50, secured: true, known: true),
        WiFiNetwork(ssid: "Office", rssi: -65, secured: true, known: true),
        WiFiNetwork(ssid: "Cafe", rssi: -58, secured: false, known: false),
        WiFiNetwork(ssid: "", rssi: -40, secured: true, known: false),
        WiFiNetwork(ssid: "Neighbour", rssi: -80, secured: true, known: false),
        WiFiNetwork(ssid: "Attic", rssi: -80, secured: true, known: false),
    ]
    let networks = WiFiNetworks(scan: scan, current: "Home")
    #expect(networks.known.map(\.ssid) == ["Office"])
    #expect(networks.other.map(\.ssid) == ["Cafe", "Attic", "Neighbour"])
    #expect(networks.other.first?.rssi == -58)
}

@Test func networkBars() {
    #expect(WiFiNetwork(ssid: "A", rssi: -55, secured: true, known: true).bars == 3)
    #expect(WiFiNetwork(ssid: "A", rssi: -75, secured: true, known: true).bars == 1)
    #expect(WiFiNetwork(ssid: "A", rssi: -90, secured: true, known: true).bars == 0)
}

@Test func joiningAKnownOrOpenNetworkStartsAtOnce() {
    var state = JoinState.idle
    #expect(state.select(WiFiNetwork(ssid: "Home", rssi: -50, secured: true, known: true)) == JoinRequest(ssid: "Home", password: nil))
    #expect(state == .joining(ssid: "Home", secured: true))
    #expect(state.select(WiFiNetwork(ssid: "Cafe", rssi: -60, secured: false, known: false)) == nil)
    state.finish(error: nil)
    #expect(state == .idle)
    #expect(state.select(WiFiNetwork(ssid: "Cafe", rssi: -60, secured: false, known: false)) == JoinRequest(ssid: "Cafe", password: nil))
    state.finish(error: "Timed out")
    #expect(state == .failed(ssid: "Cafe", error: "Timed out"))
}

@Test func aNewSecuredNetworkAsksForItsPassword() {
    let neighbour = WiFiNetwork(ssid: "Neighbour", rssi: -70, secured: true, known: false)
    var state = JoinState.idle
    #expect(state.select(neighbour) == nil)
    #expect(state == .password(ssid: "Neighbour", error: nil))
    #expect(state.submit("") == nil)
    #expect(state.submit("hunter22") == JoinRequest(ssid: "Neighbour", password: "hunter22"))
    state.cancel()
    #expect(state == .joining(ssid: "Neighbour", secured: true))
    state.finish(error: "Wrong password")
    #expect(state == .password(ssid: "Neighbour", error: "Wrong password"))
    #expect(state.select(neighbour) == nil)
    #expect(state == .idle)
}

@Test func aKnownNetworkWithoutASavedPasswordAsksForIt() {
    var state = JoinState.idle
    _ = state.select(WiFiNetwork(ssid: "Office", rssi: -65, secured: true, known: true))
    state.finish(error: "No saved password")
    #expect(state == .password(ssid: "Office", error: "No saved password"))
    state.cancel()
    #expect(state == .idle)
}
