import Foundation
import LiquidBarCore
import Testing

private func decode(_ json: String) throws -> Config {
    try Config.decode(Data(json.utf8))
}

@Test func emptyConfigReproducesTodaysBar() throws {
    let config = try decode("{}")
    #expect(config.height == 40)
    #expect(config.left == [.apple, .workspaces])
    #expect(config.right == [.volume, .wifi, .battery, .clock])
    #expect(config.workspaces.map(\.id) == ["1", "2", "3", "4", "5", "6", "7", "8", "9"])
    #expect(config.clicks["clock"] == nil)
}

@Test func overridesOnlyTheKeysGiven() throws {
    let config = try decode("""
        {"height": 36, "workspaces": [{"id": "1", "symbol": "star"}, {"id": "web"}], "clicks": {"clock": "open -a Fantastical"}}
        """)
    #expect(config.height == 36)
    #expect(config.margin == 10)
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
    #expect(throws: (any Error).self) { try decode(#"{"right": ["date"]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"height": 400}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"right": [{"symbol": "cloud"}]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"right": [{"script": "date", "interval": 0}]}"#) }
    #expect(throws: (any Error).self) { try decode(#"{"height": 40,"#) }
}
