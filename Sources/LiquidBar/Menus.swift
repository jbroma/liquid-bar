import CoreAudio
import LiquidBarCore
import SwiftUI

/// Like the Sound menu extra: the level, mute, the output devices with the current one marked, and the settings pane.
struct VolumeMenu: View {
    let model: BarModel
    @State private var devices: [OutputDevice] = []
    @State private var current: AudioObjectID = 0
    /// Paired Bluetooth headphones and speakers that are not connected, which CoreAudio does not list.
    @State private var paired: [BluetoothDevice] = []
    /// The one being connected, by address.
    @State private var connecting: String?
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        let volume = model.volume
        MenuBody {
            // Like the Wi-Fi dropdown: the switch is the sound itself, and off mutes it.
            HeaderRow(title: "Sound") {
                // At 0 the sound is off too. Switching it on from there needs a level to come back to.
                let silent = volume.muted || volume.level == 0
                Text(silent ? "Muted" : "\(volume.level)%").foregroundStyle(secondary).monospacedDigit()
                GlassSwitch(on: !silent) { on in
                    setMuted(!on)
                    if on, volume.level == 0 { model.setVolume(25) }
                }
                .accessibilityLabel("Sound")
            }
            LevelSlider(level: volume.level, muted: volume.muted, symbol: volume.symbol, height: 24, set: model.setVolume)
                .accessibilityLabel("Volume")
                .accessibilityValue("\(volume.level)%")
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            MenuSeparator()
            MenuSection(title: "Output")
            ForEach(devices) { device in
                MenuButton { setDefaultOutputDevice(device.id) } content: {
                    DeviceIcon(symbol: device.symbol, selected: device.id == current)
                    Text(device.name).lineLimit(1)
                }
            }
            ForEach(paired) { device in
                MenuButton { connect(device) } content: {
                    DeviceIcon(symbol: device.symbol, selected: false)
                    Text(device.name).lineLimit(1)
                    Spacer(minLength: 8)
                    if connecting == device.id { ProgressView().controlSize(.small) }
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
        // Switching devices changes the name the source reports, and a device coming or going changes the count; both
        // read the list and the current one again.
        .task(id: [volume.device, "\(model.audioDevicesChanges)"]) {
            devices = outputDevices()
            current = defaultOutputDevice()
            // Only with Bluetooth access already given: opening this dropdown never asks for it.
            guard Permission.bluetooth.status == .granted else { return }
            let audio: Set<String> = ["airpods", "airpodspro", "airpodsmax", "headphones", "hifispeaker"]
            paired = await Bluetooth.read().devices.filter { device in
                audio.contains(device.symbol) && !device.connected && !devices.contains { $0.name == device.name }
            }
        }
    }

    /// Connects paired headphones and makes them the output once CoreAudio lists them, as picking them in macOS's
    /// Sound menu does.
    private func connect(_ device: BluetoothDevice) {
        connecting = device.id
        Task {
            await Bluetooth.toggle(device.id)
            for _ in 0..<20 {
                if let output = outputDevices().first(where: { $0.name == device.name }) {
                    setDefaultOutputDevice(output.id)
                    break
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            connecting = nil
        }
    }
}

/// A Control Center slider: the fill always covers the symbol at its leading end. Click or drag anywhere sets the
/// level, and so does scrolling over it: about 200pt of trackpad travel crosses the range, a wheel notch moves 5%.
struct LevelSlider: View {
    let level: Int
    let muted: Bool
    let symbol: String
    var height: CGFloat = 22
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
            .overlay { ScrollCatcher(step: 2, notch: 5) { set(min(100, max(0, level + $0))) } }
        }
        .frame(height: height)
    }
}

/// An output device's symbol in a circle, filled with the accent colour for the current device.
struct DeviceIcon: View {
    let symbol: String
    let selected: Bool
    var size: CGFloat = 24
    /// How much of a variable symbol, like the Wi-Fi bars, is lit.
    var level: Double?

    var body: some View {
        Image(systemName: symbol, variableValue: level)
            .font(.system(size: size * 0.46, weight: .medium))
            .iconCircle(on: selected, size: size)
            .padding(.vertical, 2)
    }
}

/// A value row that copies its value on click and reads "Copied" for a second.
struct CopyableValue: View {
    let title: String
    let value: String
    @State private var copied = false

    var body: some View {
        MenuValue(title: title, value: copied ? "Copied" : value)
            .hoverButton {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
            }
            .task(id: copied) {
                guard copied else { return }
                try? await Task.sleep(for: .seconds(1))
                copied = false
            }
    }
}

/// Like the Battery menu extra, with the health figures from System Settings.
struct BatteryMenu: View {
    let battery: BatteryState?
    /// The bar shows the percentage beside the battery.
    let percent: Bool
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
            HeaderRow(title: "Show Percentage", bold: false) { GlassSwitch(on: percent) { Setting.batteryPercent($0).save() } }
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
                if nowPlaying.player.permission.status == .denied {
                    MenuButton { nowPlaying.player.permission.request() } content: {
                        Text("Allow Control of \(nowPlaying.player.appName)…").lineLimit(1)
                    }
                }
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
