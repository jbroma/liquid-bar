import Foundation
import LiquidBarCore
import Testing

private func decode(_ json: String) throws -> Config {
    try Config.decode(Data(json.utf8))
}

@Test func emptyConfigIsTheDefault() throws {
    let config = try decode("{}")
    #expect(config == Config())
    #expect(config.clock24Hour == nil)
    #expect([config.clockSeconds, config.batteryPercent] == [false, false])
    #expect(config.pills == .separate)
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
    #expect(display.clock24Hour == false)
    #expect([display.clockSeconds, display.batteryPercent] == [true, false])
    #expect(try decode(#"{"clock24Hour": true}"#).clock24Hour == true)
    #expect(try decode(#"{"pills": "grouped"}"#).pills == .grouped)
    // The boolean it was before the grouped layout.
    #expect(try decode(#"{"pills": false}"#).pills == PillLayout.none)
    #expect(try decode(#"{"pills": true}"#).pills == .separate)
    #expect(throws: ConfigError.self) { try decode(#"{"pills": "round"}"#) }
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
    #expect(try apply(.clock24Hour(nil), to: #"{"clock24Hour": true, "margin": 4}"#) == """
        {
          "margin" : 4
        }
        """)
    #expect(try apply(.pills(.grouped), to: #"{"glassStyle": "dew"}"#) == """
        {
          "glassStyle" : "dew",
          "pills" : "grouped"
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

@Test func pinningEditsThePinnedList() throws {
    let pinned = try apply(.pinned("com.example.a", true), to: #"{"margin": 4}"#)
    #expect(pinned == """
        {
          "margin" : 4,
          "pinned" : [
            "com.example.a"
          ]
        }
        """)
    let two = try apply(.pinned("com.example.b", true), to: pinned)
    #expect(try decode(two).pinned == ["com.example.a", "com.example.b"])
    #expect(try apply(.pinned("com.example.a", true), to: two) == two)
    #expect(try apply(.pinned("com.example.a", false), to: two) == """
        {
          "margin" : 4,
          "pinned" : [
            "com.example.b"
          ]
        }
        """)
    #expect(try apply(.pinned("com.example.b", false), to: #"{"pinned": ["com.example.b"], "x": 1}"#) == """
        {
          "pinned" : [

          ],
          "x" : 1
        }
        """)
}

@Test func decodesPinnedApps() throws {
    #expect(try decode(#"{"pinned": ["a", "b", "a"]}"#).pinned == ["a", "b"])
    #expect(try decode("{}").pinned == [])
    #expect(throws: (any Error).self) { try decode(#"{"pinned": [""]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"pinned": "a"}"#) }
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

@Test func decodesTheGlassStyle() throws {
    #expect(try decode("{}").glassStyle == .liquid)
    #expect(try decode(#"{"glassStyle": "obsidian"}"#).glassStyle == .obsidian)
    #expect(try decode(#"{"glassStyle": "dew"}"#).glassStyle == .dew)
    #expect(try decode(#"{"glassStyle": "pearl"}"#).glassStyle == .pearl)
    #expect(GlassStyle.allCases.map(\.rawValue) == ["liquid", "dew", "pearl", "crystal", "frost", "mist", "obsidian"])
    #expect(GlassStyle.allCases.map(\.title) == ["Liquid", "Dew", "Pearl", "Crystal", "Frost", "Mist", "Obsidian"])
    #expect(throws: (any Error).self) { try decode(#"{"glassStyle": "Obsidian"}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"glassStyle": "volume"}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"glassStyle": 1}"#) }
}

@Test func dewAndPearlAreEvenStepsFromLiquidToCrystal() {
    let percents = GlassStyle.allCases.compactMap(\.blend).map { blend in
        [blend.liquid, blend.pillFill, blend.pillOutline].map { ($0 * 100).rounded() }
    }
    #expect(percents == [[100, 14, 0], [67, 11, 10], [33, 8, 20], [0, 5, 30]])
    #expect([GlassStyle.liquid.blend?.pillFill, GlassStyle.liquid.blend?.pillOutline] == [0.14, 0])
    #expect([GlassStyle.crystal.blend?.pillFill, GlassStyle.crystal.blend?.pillOutline] == [0.05, 0.3])
    #expect(GlassStyle.frost.blend == nil)
}

@Test func glassStyleEditsTheConfig() throws {
    #expect(try apply(.glassStyle(.mist), to: #"{"glassStyle": "crystal", "margin": 4}"#) == """
        {
          "glassStyle" : "mist",
          "margin" : 4
        }
        """)
}

@Test func pinnedOrderReplacesThePinnedList() throws {
    #expect(try apply(.pinnedOrder(["com.example.b", "com.example.a"]), to: #"{"pinned": ["com.example.a", "com.example.b"]}"#) == """
        {
          "pinned" : [
            "com.example.b",
            "com.example.a"
          ]
        }
        """)
}

@Test func barAndDropdownStylesOverrideThePreset() throws {
    let none = try decode(#"{"glassStyle": "mist"}"#)
    #expect(none.glass == GlassPair(bar: .mist, dropdown: .mist))
    #expect(!none.glassIsCustom)
    let bar = try decode(#"{"glassStyle": "mist", "barStyle": "crystal"}"#)
    #expect(bar.glass == GlassPair(bar: .crystal, dropdown: .mist))
    #expect(bar.glassIsCustom)
    let both = try decode(#"{"barStyle": "frost", "dropdownStyle": "dew"}"#)
    #expect(both.glass == GlassPair(bar: .frost, dropdown: .dew))
    #expect(!(try decode(#"{"glassStyle": "dew", "dropdownStyle": "dew"}"#)).glassIsCustom)
    #expect(throws: (any Error).self) { try decode(#"{"barStyle": "Crystal"}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"dropdownStyle": "volume"}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"dropdownStyle": 1}"#) }
}

@Test func barAndDropdownStylesEditTheConfig() throws {
    #expect(try apply(.barStyle(.crystal), to: #"{"glassStyle": "mist", "margin": 4}"#) == """
        {
          "barStyle" : "crystal",
          "glassStyle" : "mist",
          "margin" : 4
        }
        """)
    #expect(try apply(.dropdownStyle(nil), to: #"{"barStyle": "crystal", "dropdownStyle": "dew", "margin": 4}"#) == """
        {
          "barStyle" : "crystal",
          "margin" : 4
        }
        """)
    #expect(try apply(.glassStyle(.pearl), to: #"{"barStyle": "crystal", "dropdownStyle": "dew", "margin": 4}"#) == """
        {
          "glassStyle" : "pearl",
          "margin" : 4
        }
        """)
}
