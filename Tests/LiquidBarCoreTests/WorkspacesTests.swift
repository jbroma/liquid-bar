import Foundation
import LiquidBarCore
import Testing

@Test func autoPrefersAeroSpaceThenDesktopsThenApps() {
    #expect(WorkspaceSource.auto.resolved(aerospaceRunning: true, desktops: 3) == .aerospace)
    #expect(WorkspaceSource.auto.resolved(aerospaceRunning: false, desktops: 2) == .spaces)
    #expect(WorkspaceSource.auto.resolved(aerospaceRunning: false, desktops: 1) == .apps)
    #expect(WorkspaceSource.apps.resolved(aerospaceRunning: true, desktops: 3) == .apps)
    #expect(WorkspaceSource.spaces.resolved(aerospaceRunning: false, desktops: 1) == .spaces)
}

/// `SLSCopyManagedDisplaySpaces` as read live on a Mac with one display and one desktop.
nonisolated(unsafe) private let liveOneDesktop: [[String: Any]] = [[
    "Current Space": ["ManagedSpaceID": 1, "id64": 1, "type": 0, "uuid": ""],
    "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
    "Spaces": [["ManagedSpaceID": 1, "id64": 1, "type": 0, "uuid": ""]],
]]

/// The same shape with three desktops around a fullscreen app, the third one current, and a second display.
nonisolated(unsafe) private let threeDesktops: [[String: Any]] = [
    [
        "Current Space": ["ManagedSpaceID": 9, "id64": 9, "type": 0, "uuid": "C"],
        "Display Identifier": "Main",
        "Spaces": [
            ["ManagedSpaceID": 1, "id64": 1, "type": 0, "uuid": ""],
            ["ManagedSpaceID": 4, "id64": 4, "type": 0, "uuid": "B"],
            ["ManagedSpaceID": 7, "id64": 7, "type": 4, "uuid": "F", "fs_wid": 88],
            ["ManagedSpaceID": 9, "id64": 9, "type": 0, "uuid": "C"],
        ],
    ],
    ["Display Identifier": "Side", "Spaces": [["ManagedSpaceID": 12, "id64": 12, "type": 0, "uuid": "D"]]],
    ["Spaces": []],
]

@Test func parsesDesktopsWithoutFullscreenSpaces() {
    #expect(parseDisplaySpaces(liveOneDesktop) == [DisplaySpaces(display: "37D8832A-2D66-02CA-B9F7-8F30A301B230", desktops: [1], current: 1)])
    #expect(parseDisplaySpaces(threeDesktops) == [
        DisplaySpaces(display: "Main", desktops: [1, 4, 9], current: 9),
        DisplaySpaces(display: "Side", desktops: [12], current: nil),
    ])
}

@Test func desktopsAreNumberedWithTheirAppsFrontFirst() {
    let desktops = DisplaySpaces(display: "Main", desktops: [1, 4, 9], current: 9)
    let owners = [10: "com.example.browser", 11: "com.apple.Notes", 12: "com.example.browser", 13: "com.example.chat", 20: "com.apple.MobileSMS"]
    // 99 has no owner (a system window) and 20 is on every desktop.
    let state = WorkspaceState(desktops: desktops, windows: [1: [10, 11, 20], 4: [], 9: [13, 99, 12, 20]], owners: owners)
    #expect(state.source == .spaces)
    #expect(state.ids == ["1", "2", "3"])
    #expect(state.focused == "3")
    #expect(state.title("3") == "Desktop 3")
    #expect(state.apps(on: "3") == [
        WorkspaceApp(bundleID: "com.example.chat", windowID: 13, focused: true),
        WorkspaceApp(bundleID: "com.example.browser", windowID: 12, focused: false),
        WorkspaceApp(bundleID: "com.apple.MobileSMS", windowID: 20, focused: false),
    ])
    // A window on every desktop keeps the rank it has on the current one.
    #expect(state.apps(on: "1").map(\.bundleID) == ["com.apple.MobileSMS", "com.example.browser", "com.apple.Notes"])
    #expect(state.occupied == ["1", "3"])
    #expect(state.neighbor(-1, in: state.ids) == "1")
}

@Test func onlyTheFirstNineDesktopsAreShown() {
    let state = WorkspaceState(desktops: DisplaySpaces(display: "Main", desktops: Array(1...12), current: 11), windows: [:], owners: [:])
    #expect(state.ids == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
    #expect(state.focused == nil)
}

@Test func appsAreOrderedByActivationWithTheFrontAppFocused() {
    let apps = [
        RunningApp(pid: 5, bundleID: "com.apple.Notes"),
        RunningApp(pid: 7, bundleID: "com.example.browser"),
        RunningApp(pid: 9, bundleID: "com.example.chat"),
        RunningApp(pid: 3, bundleID: "com.apple.MobileSMS"),
    ]
    let state = WorkspaceState(apps: apps, recency: [9, 42, 5])
    #expect(state.ids == ["com.example.chat", "com.apple.Notes", "com.example.browser", "com.apple.MobileSMS"])
    #expect(state.focused == "com.example.chat")
    #expect(state.numbered == false)
    #expect(state.apps(on: "com.apple.Notes") == [WorkspaceApp(bundleID: "com.apple.Notes", windowID: 5, focused: false)])
    // The front app has no windows, so nothing is focused.
    #expect(WorkspaceState(apps: apps, recency: [42, 7]).focused == nil)
    #expect(WorkspaceState(apps: apps, recency: [42, 7]).ids.first == "com.example.browser")
}

@Test func readsTheSwitchToDesktopShortcutsOnlyWhenEnabled() {
    let hotkeys: [String: Any] = [
        "118": ["enabled": true, "value": ["parameters": [65535, 18, 262144], "type": "standard"]],
        "119": ["enabled": false, "value": ["parameters": [65535, 19, 262144], "type": "standard"]],
        "120": ["enabled": 1, "value": ["parameters": [65535, 20, 786432], "type": "standard"]],
    ]
    #expect(desktopShortcut(1, in: hotkeys) == KeyShortcut(keyCode: 18, modifiers: 262144))
    #expect(desktopShortcut(2, in: hotkeys) == nil)
    #expect(desktopShortcut(3, in: hotkeys) == KeyShortcut(keyCode: 20, modifiers: 786432))
    #expect(desktopShortcut(4, in: hotkeys) == nil)
}
