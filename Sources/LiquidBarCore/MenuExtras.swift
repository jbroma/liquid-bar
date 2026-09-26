import Foundation

/// A status item another app put in the native menu bar, which the bar covers. `Handle` is what presses it.
public struct MenuExtra<Handle> {
    public var bundleID: String
    public var appName: String
    /// The item's own title or description, when it sets a non-empty one.
    public var label: String?
    /// Its left edge in the native menu bar.
    public var x: Double
    public var handle: Handle

    public init(bundleID: String, appName: String, title: String?, description: String?, x: Double, handle: Handle) {
        self.bundleID = bundleID
        self.appName = appName
        self.label = [title, description].compactMap { $0 }.first { !$0.isEmpty }
        self.x = x
        self.handle = handle
    }
}

extension MenuExtra: Equatable where Handle: Equatable {}
extension MenuExtra: Sendable where Handle: Sendable {}

/// The tray's rows, in the native menu bar's left-to-right order. Apple's items, which the bar replaces, and
/// AeroSpace's, whose workspace the bar shows, are left out.
public func trayItems<Handle>(_ extras: [MenuExtra<Handle>]) -> [MenuExtra<Handle>] {
    extras.filter { !$0.bundleID.hasPrefix("com.apple.") && $0.bundleID != "bobko.aerospace" }.sorted { $0.x < $1.x }
}
