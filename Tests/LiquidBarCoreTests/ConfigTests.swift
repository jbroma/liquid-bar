import Foundation
import LiquidBarCore
import Testing

private func decode(_ json: String) throws -> Config {
    try Config.decode(Data(json.utf8))
}

@Test func emptyConfigIsTheDefault() throws {
    let config = try decode("{}")
    #expect(config == Config())
    #expect([config.clock24Hour, config.clockSeconds, config.batteryPercent] == [true, false, true])
}

@Test func overridesOnlyTheKeysGiven() throws {
    let config = try decode("""
        {"margin": 4, "workspaces": [{"id": "1"}, {"id": "web"}], "clicks": {"clock": "open -a Fantastical"}}
        """)
    #expect(config.margin == 4)
    #expect(config.workspaceSource == .auto)
    #expect(try decode(#"{"workspaceSource": "spaces"}"#).workspaceSource == .spaces)
    #expect(try decode(#"{"unknown": true}"#) == Config())
    let display = try decode(#"{"clock24Hour": false, "clockSeconds": true, "batteryPercent": false}"#)
    #expect([display.clock24Hour, display.clockSeconds, display.batteryPercent] == [false, true, false])
    #expect(config.workspaces == [Workspace(id: "1"), Workspace(id: "web")])
    #expect(config.clicks["clock"] == "open -a Fantastical")
    #expect(config.clicks["volume"] == "open 'x-apple.systempreferences:com.apple.Sound-Settings.extension'")
}

@Test func decodesScriptWidgets() throws {
    let config = try decode("""
        {"right": ["clock", {"script": "echo hi", "symbol": "cloud", "interval": 600, "on": ["weather"], "click": "open -a Weather"}]}
        """)
    #expect(config.right == [
        .clock,
        .script(ScriptWidget(script: "echo hi", symbol: "cloud", interval: 600, on: ["weather"], click: "open -a Weather")),
    ])
}

@Test func rejectsInvalidConfig() {
    #expect(throws: (any Error).self) { try decode(#"{"right": ["clok"]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"margin": -1}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"right": [{"symbol": "cloud"}]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"right": [{"script": "date", "interval": 0}]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"margin": 4,"#) }
    #expect(throws: (any Error).self) { try decode(#"{"workspaceSource": "desktops"}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"clockSeconds": "yes"}"#) }
}

private func apply(_ setting: Setting, to json: String?) throws -> String {
    String(decoding: try setting.applied(to: json.map { Data($0.utf8) }), as: UTF8.self)
}

@Test func settingsEditTheConfigKeepingOtherKeys() throws {
    #expect(try apply(.clockSeconds(true), to: nil) == """
        {
          "clockSeconds" : true
        }
        """)
    #expect(try apply(.workspaceSource(.apps), to: #"{"margin": 4, "workspaceSource": "auto", "x": [1]}"#) == """
        {
          "margin" : 4,
          "workspaceSource" : "apps",
          "x" : [
            1
          ]
        }
        """)
    #expect(try apply(.batteryPercent(false), to: "{}") == """
        {
          "batteryPercent" : false
        }
        """)
    #expect(try apply(.clock24Hour(false), to: #"{"clock24Hour": true}"#) == """
        {
          "clock24Hour" : false
        }
        """)
    #expect(throws: (any Error).self) { try apply(.clockSeconds(true), to: "[]") }
    #expect(throws: (any Error).self) { try apply(.clockSeconds(true), to: #"{"margin": "#) }
}

@Test func nowPlayingTogglesInTheRightList() throws {
    let hidden = try apply(.nowPlaying(false), to: nil)
    #expect(hidden == """
        {
          "right" : [
            "volume",
            "wifi",
            "battery",
            "controlCenter",
            "clock"
          ]
        }
        """)
    #expect(try decode(try apply(.nowPlaying(true), to: hidden)).right == Config().right)
    #expect(try apply(.nowPlaying(true), to: #"{"right": ["clock", {"script": "date"}]}"#) == """
        {
          "right" : [
            "nowPlaying",
            "clock",
            {
              "script" : "date"
            }
          ]
        }
        """)
    #expect(try apply(.nowPlaying(true), to: #"{"right": ["clock", "nowPlaying"]}"#) == """
        {
          "right" : [
            "clock",
            "nowPlaying"
          ]
        }
        """)
}

@Test func createsAMissingConfigFileOnly() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "liquid-bar/config.json")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
    try createConfigFile(at: url)
    #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == "{}\n")
    try Data(#"{"margin": 4}"#.utf8).write(to: url)
    try createConfigFile(at: url)
    #expect(String(decoding: try Data(contentsOf: url), as: UTF8.self) == #"{"margin": 4}"#)
}
