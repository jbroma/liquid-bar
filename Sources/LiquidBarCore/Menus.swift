import Foundation

/// Battery wear from the `AppleSmartBattery` registry entry, which any process may read.
public struct BatteryHealth: Equatable, Sendable {
    public var cycleCount: Int?
    /// Full charge capacity as a percentage of the design capacity, like System Settings' "Maximum Capacity".
    public var maxCapacity: Int?
    public var serviceRecommended: Bool

    public init(cycleCount: Int?, maxCapacity: Int?, serviceRecommended: Bool) {
        self.cycleCount = cycleCount
        self.maxCapacity = maxCapacity
        self.serviceRecommended = serviceRecommended
    }

    /// Nil when the entry carries none of the keys, as on a desktop Mac.
    public init?(registry: [String: Any]) {
        let cycles = registry["CycleCount"] as? Int
        let full = registry["NominalChargeCapacity"] as? Int ?? registry["AppleRawMaxCapacity"] as? Int
        let design = registry["DesignCapacity"] as? Int
        let failure = registry["PermanentFailureStatus"] as? Int
        guard cycles != nil || full != nil || failure != nil else { return nil }
        self.cycleCount = cycles
        self.maxCapacity = full.flatMap { full in design.flatMap { $0 > 0 ? Int((Double(full) * 100 / Double($0)).rounded()) : nil } }
        self.serviceRecommended = (failure ?? 0) != 0
    }

    public var condition: String { serviceRecommended ? "Service Recommended" : "Normal" }
}

extension BatteryState {
    /// "100 W Adapter", "Power Adapter", "Battery".
    public func powerSource(watts: Int?) -> String {
        guard onAC else { return "Battery" }
        return watts.map { "\($0) W Adapter" } ?? "Power Adapter"
    }
}

extension VolumeState {
    /// The level for a slider position `x` along a track `width` points wide, clamped to 0...100.
    public static func level(at x: Double, width: Double) -> Int {
        guard width > 0 else { return 0 }
        return min(100, max(0, Int((x / width * 100).rounded())))
    }
}

/// The SF Symbol for an output device, from its CoreAudio transport type (a four-character code) and its name.
public func outputDeviceSymbol(transport: UInt32, name: String) -> String {
    if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
    if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
    if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
    switch fourCC(transport) {
    case "bltn": return "laptopcomputer"
    case "blue", "blea": return "headphones"
    case "airp": return "airplayaudio"
    case "hdmi", "dprt": return "tv"
    case "usb ": return "hifispeaker"
    default: return "speaker.wave.2"
    }
}

private func fourCC(_ code: UInt32) -> String {
    String(decoding: [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }, as: UTF8.self)
}

/// Where a dropdown `width` wide starts: centred under the item at `center`, kept within `lower...upper - width`.
public func dropdownX(center: Double, width: Double, lower: Double, upper: Double) -> Double {
    max(lower, min(center - width / 2, upper - width))
}
