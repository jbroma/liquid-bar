import CoreAudio
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
            MenuRow { VolumeSlider(level: volume.level, muted: volume.muted, set: model.setVolume) }
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

/// The volume overlay's slider: a thin track between a quiet and a loud speaker. Click, drag or scroll sets the level.
struct VolumeSlider: View {
    let level: Int
    let muted: Bool
    let set: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(muted ? 0.4 : 1)).frame(width: width * CGFloat(level) / 100)
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { set(VolumeState.level(at: $0.location.x, width: width)) })
                .overlay { ScrollCatcher(step: 2, notch: 5) { set(min(100, max(0, level + $0))) } }
            }
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 12, weight: .semibold))
        .frame(height: 24)
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
