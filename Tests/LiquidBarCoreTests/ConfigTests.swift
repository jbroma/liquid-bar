import Foundation
import LiquidBarCore
import Testing

private func decode(_ json: String) throws -> Config {
    try Config.decode(Data(json.utf8))
}

@Test func emptyConfigIsTheDefault() throws {
    #expect(try decode("{}") == Config())
}

@Test func overridesOnlyTheKeysGiven() throws {
    let config = try decode("""
        {"margin": 4, "workspaces": [{"id": "1"}, {"id": "web"}], "clicks": {"clock": "open -a Fantastical"}}
        """)
    #expect(config.margin == 4)
    #expect(config.workspaceSource == .auto)
    #expect(try decode(#"{"workspaceSource": "spaces"}"#).workspaceSource == .spaces)
    #expect(try decode(#"{"unknown": true}"#) == Config())
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
}
