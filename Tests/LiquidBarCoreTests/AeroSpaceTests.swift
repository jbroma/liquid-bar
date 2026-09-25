import LiquidBarCore
import Testing

@Test func parsesRealSubscribeLines() {
    #expect(parseAeroEvent(#"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"3"}"#) == .workspaceChanged("3"))
    #expect(parseAeroEvent(#"{"_event":"focus-changed","windowId":53611,"workspace":"1"}"#) == .focusChanged(workspace: "1"))
    #expect(parseAeroEvent(#"{"_event":"focus-changed"}"#) == .focusChanged(workspace: nil))
    #expect(parseAeroEvent(#"{"_event":"mode-changed","mode":"service"}"#) == .modeChanged("service"))
    #expect(parseAeroEvent(#"{"_event":"window-detected","windowId":7,"workspace":"2","appBundleId":"com.apple.Notes"}"#) == .windowDetected)
}

@Test func ignoresUnknownOrBrokenLines() {
    #expect(parseAeroEvent(#"{"_event":"binding-triggered","binding":"alt-1"}"#) == nil)
    #expect(parseAeroEvent("not json") == nil)
    #expect(parseAeroEvent(#"{"_event":"mode-changed"}"#) == nil)
}

@Test func occupancyFromListWindowsOutput() {
    #expect(parseOccupied("8\n2\n4\n6\n4\n1\n") == ["1", "2", "4", "6", "8"])
    #expect(parseOccupied("  3 \n\n") == ["3"])
    #expect(parseOccupied("") == [])
}

@Test func eventsUpdateStateAndRequestRefresh() {
    var state = WorkspaceState(focused: "1", occupied: ["1"], mode: "main")
    #expect(state.apply(.workspaceChanged("3")) == false)
    #expect(state.focused == "3")
    #expect(state.apply(.focusChanged(workspace: "2")) == true)
    #expect(state.focused == "2")
    #expect(state.apply(.focusChanged(workspace: nil)) == true)
    #expect(state.focused == "2")
    #expect(state.apply(.modeChanged("service")) == false)
    #expect(state == WorkspaceState(focused: "2", occupied: ["1"], mode: "service"))
}
