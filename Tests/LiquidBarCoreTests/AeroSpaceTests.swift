import LiquidBarCore
import Testing

@Test func parsesRealSubscribeLines() {
    #expect(parseAeroEvent(#"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"3"}"#) == .workspaceChanged("3"))
    #expect(parseAeroEvent(#"{"_event":"focus-changed","windowId":53611,"workspace":"1"}"#) == .focusChanged(workspace: "1", windowID: 53611))
    #expect(parseAeroEvent(#"{"_event":"focus-changed"}"#) == .focusChanged(workspace: nil, windowID: nil))
    #expect(parseAeroEvent(#"{"_event":"mode-changed","mode":"service"}"#) == .modeChanged("service"))
    #expect(parseAeroEvent(#"{"_event":"window-detected","windowId":7,"workspace":"2","appBundleId":"com.apple.Notes"}"#) == .windowDetected)
}

@Test func ignoresUnknownOrBrokenLines() {
    #expect(parseAeroEvent(#"{"_event":"binding-triggered","binding":"alt-1"}"#) == nil)
    #expect(parseAeroEvent("not json") == nil)
    #expect(parseAeroEvent(#"{"_event":"mode-changed"}"#) == nil)
}

private let listing = """
    8|412|com.example.chat
    2|388|com.example.browser
    4|120|com.apple.MobileSMS
    6|77|com.apple.Notes
    4|121|com.example.editor
    1|5|com.github.wez.wezterm
    4|122|com.apple.MobileSMS

    garbage line
    """

@Test func parsesWorkspaceWindowBundleIDs() {
    let windows = parseWindows(listing)
    #expect(windows.count == 7)
    #expect(windows[0] == Window(id: 412, workspace: "8", bundleID: "com.example.chat"))
    #expect(windows[6] == Window(id: 122, workspace: "4", bundleID: "com.apple.MobileSMS"))
    var state = WorkspaceState()
    state.setWindows(windows)
    #expect(state.occupied == ["1", "2", "4", "6", "8"])
    #expect(state.apps(on: "4").map(\.bundleID) == ["com.apple.MobileSMS", "com.example.editor"])
    #expect(state.apps(on: "3").map(\.bundleID) == [])
}

@Test func mostRecentlyFocusedAppComesFirst() {
    var state = WorkspaceState()
    state.setWindows(parseWindows(listing))
    #expect(state.apply(.focusChanged(workspace: "4", windowID: 121)) == true)
    #expect(state.apps(on: "4").map(\.bundleID) == ["com.example.editor", "com.apple.MobileSMS"])
    _ = state.apply(.focusChanged(workspace: "4", windowID: 122))
    #expect(state.apps(on: "4").map(\.bundleID) == ["com.apple.MobileSMS", "com.example.editor"])
    #expect(state.recency == [122, 121])
    state.setWindows(parseWindows("4|121|com.example.editor\n"))
    #expect(state.recency == [121])
    #expect(state.focused == "4")
}

@Test func workspaceRowsCarryTheWindowToFocusAndMarkTheFocusedApp() {
    var state = WorkspaceState()
    state.setWindows(parseWindows(listing))
    #expect(state.apps(on: "4") == [
        WorkspaceApp(bundleID: "com.apple.MobileSMS", windowID: 120, focused: false),
        WorkspaceApp(bundleID: "com.example.editor", windowID: 121, focused: false),
    ])
    _ = state.apply(.focusChanged(workspace: "4", windowID: 121))
    _ = state.apply(.focusChanged(workspace: "4", windowID: 122))
    #expect(state.apps(on: "4") == [
        WorkspaceApp(bundleID: "com.apple.MobileSMS", windowID: 122, focused: true),
        WorkspaceApp(bundleID: "com.example.editor", windowID: 121, focused: false),
    ])
    // On another, empty workspace the last focused window keeps its rank but is no longer the focused one.
    _ = state.apply(.workspaceChanged("3"))
    #expect(state.apps(on: "4").map(\.focused) == [false, false])
    #expect(state.apps(on: "4").map(\.windowID) == [122, 121])
}

@Test func eventsUpdateFocusAndMode() {
    var state = WorkspaceState(focused: "1")
    #expect(state.apply(.workspaceChanged("3")) == false)
    #expect(state.focused == "3")
    #expect(state.apply(.focusChanged(workspace: nil, windowID: nil)) == true)
    #expect(state.focused == "3")
    #expect(state.apply(.modeChanged("service")) == false)
    #expect(state == WorkspaceState(focused: "3", mode: "service"))
}

@Test func scrollingStepsThroughOccupiedWorkspaces() {
    let order = (1...9).map(String.init)
    var state = WorkspaceState(focused: "2")
    state.setWindows(parseWindows(listing))
    #expect(state.neighbor(1, in: order) == "4")
    #expect(state.neighbor(-1, in: order) == "1")
    #expect(state.neighbor(-5, in: order) == "1")
    #expect(state.neighbor(9, in: order) == "8")
    state.focused = "3"
    #expect(state.neighbor(1, in: order) == "4")
    #expect(state.neighbor(-1, in: order) == "2")
}
