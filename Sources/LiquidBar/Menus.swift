import CoreAudio
import CoreWLAN
import LiquidBarCore
import SwiftUI

/// Like the Sound menu extra: the level, mute, the output devices with the current one marked, and the settings pane.
struct VolumeMenu: View {
    let model: BarModel
    @State private var devices: [OutputDevice] = []
    @State private var current: AudioObjectID = 0
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        let volume = model.volume
        MenuBody {
            MenuTitle(title: "Sound", accessory: volume.muted ? "Muted" : "\(volume.level)%")
            MenuRow { LevelSlider(level: volume.level, muted: volume.muted, symbol: volume.symbol, set: model.setVolume) }
            MenuButton { setMuted(!volume.muted) } content: {
                Text("Mute")
                Spacer()
                if volume.muted { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
            MenuSeparator()
            MenuSection(title: "Output")
            ForEach(devices) { device in
                MenuButton { setDefaultOutputDevice(device.id) } content: {
                    DeviceIcon(symbol: device.symbol, selected: device.id == current)
                    Text(device.name).lineLimit(1)
                }
            }
            // CoreAudio lists an AirPlay receiver only while it plays; Control Center's Sound module lists them all.
            MenuButton {
                slot.dismiss()
                showControlCenterModule("controlcenter-volume", else: "com.apple.Sound-Settings.extension")
            } content: {
                DeviceIcon(symbol: "airplayaudio", selected: false)
                Text("AirPlay…")
            }
            MenuSeparator()
            SettingsButton(title: "Sound Settings…", pane: "com.apple.Sound-Settings.extension")
        }
        // Switching devices changes the name the source reports, which re-reads the list and the current one.
        .task(id: volume.device) {
            devices = outputDevices()
            current = defaultOutputDevice()
        }
    }
}

/// A Control Center slider: the fill always covers the symbol at its leading end. Click or drag anywhere sets the level.
struct LevelSlider: View {
    let level: Int
    let muted: Bool
    let symbol: String
    let set: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let knob = proxy.size.height
            let travel = proxy.size.width - knob
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(.white.opacity(muted ? 0.4 : 1))
                    .frame(width: knob + travel * CGFloat(level) / 100)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(width: knob)
            }
            .contentShape(Capsule())
            .gesture(DragGesture(minimumDistance: 0).onChanged { set(VolumeState.level(at: $0.location.x - knob / 2, width: travel)) })
        }
        .frame(height: 22)
    }
}

/// An output device's symbol in a circle, filled white for the current device.
struct DeviceIcon: View {
    let symbol: String
    let selected: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .medium))
            .iconCircle(on: selected, size: 24)
            .padding(.vertical, 2)
    }
}

/// Like the Wi-Fi menu extra: the network, its address and live throughput. Throughput is sampled once a second only
/// while the menu is open.
struct NetworkMenu: View {
    let network: NetworkState
    @State private var name: String?
    @State private var bars: Int?
    @State private var address: String?
    @State private var rates: (down: Double, up: Double)?

    var body: some View {
        MenuBody {
            MenuTitle(title: network.kind == .wired ? "Ethernet" : "Wi-Fi", accessory: network.interface ?? "Not Connected")
            if network.kind != .offline {
                MenuRow {
                    DeviceIcon(symbol: network.symbol, selected: true)
                    // The SSID needs Location access; without it CoreWLAN returns nil and the signal stands in.
                    Text(name ?? (network.kind == .wifi ? "Wi-Fi Network" : "Connected")).lineLimit(1)
                    Spacer(minLength: 8)
                    if let bars { Image(systemName: "wifi", variableValue: Double(bars) / 3).foregroundStyle(secondary) }
                }
                MenuSeparator()
                MenuValue(title: "IP Address", value: address ?? "None")
                MenuValue(title: "Download", value: throughputText(rates?.down ?? 0))
                MenuValue(title: "Upload", value: throughputText(rates?.up ?? 0))
            }
            MenuSeparator()
            SettingsButton(title: "Network Settings…", pane: "com.apple.Network-Settings.extension")
        }
        .task(id: network) { await sample() }
    }

    private func sample() async {
        let wifi = network.kind == .wifi ? CWWiFiClient.shared().interface() : nil
        name = wifi?.ssid()
        bars = wifi.map { signalBars(rssi: $0.rssiValue()) }
        address = network.interface.flatMap(ipv4Address)
        guard let interface = network.interface, var last = interfaceBytes(interface) else { return }
        var lastTime = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let now = interfaceBytes(interface) else { return }
            let elapsed = Date().timeIntervalSince(lastTime)
            rates = (Double(now.received &- last.received) / elapsed, Double(now.sent &- last.sent) / elapsed)
            last = now
            lastTime = Date()
        }
    }
}

/// Like the Battery menu extra, with the health figures from System Settings.
struct BatteryMenu: View {
    let battery: BatteryState?
    @State private var health: BatteryHealth?
    @State private var watts: Int?

    var body: some View {
        MenuBody {
            if let battery {
                MenuTitle(title: "Battery", accessory: "\(battery.percent)%")
                MenuRow { Meter(value: Double(battery.percent) / 100, tint: battery.tint.color, width: 236, height: 6) }
                MenuValue(title: "Power Source", value: battery.powerSource(watts: watts))
                MenuValue(title: "Status", value: battery.detail)
                if let health {
                    MenuSeparator()
                    MenuSection(title: "Health")
                    MenuValue(title: "Condition", value: health.condition)
                    if let capacity = health.maxCapacity { MenuValue(title: "Maximum Capacity", value: "\(capacity)%") }
                    if let cycles = health.cycleCount { MenuValue(title: "Cycle Count", value: "\(cycles)") }
                }
                MenuSeparator()
            }
            SettingsButton(title: "Battery Settings…", pane: "com.apple.Battery-Settings.extension")
        }
        .task(id: battery) {
            health = readBatteryHealth()
            watts = battery?.onAC == true ? adapterWatts() : nil
        }
    }
}

/// Like the Now Playing module in Control Center: artwork, title, artist and the transport controls.
struct NowPlayingMenu: View {
    let nowPlaying: NowPlaying?
    let artwork: NSImage?
    let control: (String) -> Void

    var body: some View {
        MenuBody {
            if let nowPlaying {
                MenuRow {
                    Artwork(image: artwork, size: 56, radius: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Marquee(text: nowPlaying.title, font: .system(size: 13, weight: .semibold), width: 176)
                        Marquee(text: nowPlaying.artist, font: .system(size: 13), width: 176)
                            .foregroundStyle(secondary)
                        Text(nowPlaying.player.appName)
                            .font(.system(size: 11))
                            .foregroundStyle(secondary)
                    }
                    .padding(.leading, 2)
                }
                .padding(.vertical, 4)
                HStack(spacing: 12) {
                    TransportButton(symbol: "backward.fill") { control("previous track") }
                    TransportButton(symbol: nowPlaying.playing ? "pause.fill" : "play.fill") { control("playpause") }
                    TransportButton(symbol: "forward.fill") { control("next track") }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                MenuSeparator()
                MenuButton { shell("open -b \(nowPlaying.player.rawValue)") } content: { Text("Open \(nowPlaying.player.appName)") }
            }
        }
    }
}

private struct TransportButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 44, height: 30)
            .hoverButton(action: action)
    }
}
