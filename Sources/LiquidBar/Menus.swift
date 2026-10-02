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
    /// The health details start folded, like the Wi-Fi networks, and fold again when the dropdown closes.
    @State private var detailed = false
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        MenuBody {
            if let battery {
                HeaderRow(title: "Battery") { Text("\(battery.percent)%").foregroundStyle(secondary).monospacedDigit() }
                BatteryBar(level: Double(battery.percent) / 100, charging: battery.charging, fill: battery.tint.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
                // One line: what the battery is doing, and what powers the Mac.
                MenuRow {
                    Text(battery.detail).monospacedDigit().lineLimit(1)
                    Spacer(minLength: 8)
                    Text(battery.powerSource(watts: watts)).foregroundStyle(secondary).lineLimit(1)
                }
                if let health {
                    MenuSeparator()
                    HeaderRow(title: "Battery Health", bold: false) {
                        Text(health.condition).foregroundStyle(secondary)
                        Disclosure(open: detailed)
                    }
                    .hoverButton { withAnimation(spring) { detailed.toggle() } }
                    if detailed {
                        Group {
                            if let capacity = health.maxCapacity { MenuValue(title: "Maximum Capacity", value: "\(capacity)%") }
                            if let cycles = health.cycleCount { MenuValue(title: "Cycle Count", value: "\(cycles)") }
                        }
                        .transition(.opacity)
                    }
                }
                MenuSeparator()
            }
            HeaderRow(title: "Show Percentage", bold: false) { GlassSwitch(on: percent) { Setting.batteryPercent($0).save() } }
            SettingsButton(title: "Battery Settings…", pane: "com.apple.Battery-Settings.extension")
        }
        .onChange(of: slot.owner == .battery) { _, open in if !open { detailed = false } }
        .task(id: battery) {
            health = readBatteryHealth()
            watts = battery?.onAC == true ? adapterWatts() : nil
        }
    }
}

/// The charge as a wide bar, like Control Center's sliders. While charging it is a liquid on its side: the surface at
/// the end of the fill rolls in three layers and sloshes slowly, bubbles drift along the fill and fade at the surface,
/// and a soft light lies along its top. The clock runs only while charging.
struct BatteryBar: View {
    let level: Double
    let charging: Bool
    let fill: Color
    private let height: CGFloat = 24

    var body: some View {
        TimelineView(.animation(paused: !charging)) { timeline in
            GeometryReader { proxy in
                let width = height + (proxy.size.width - height) * level
                let time = charging ? timeline.date.timeIntervalSinceReferenceDate : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                    if charging {
                        // The whole surface leans in and out, as a liquid settles.
                        let end = width + 2.5 * sin(time * 1.3)
                        let surface = LiquidEdge(end: end, time: time, amplitude: 4)
                        // Two fainter waves behind the surface, each a little ahead and out of step.
                        LiquidEdge(end: end + 5, time: time * 0.8 + 4, amplitude: 5).fill(fill.opacity(0.22))
                        LiquidEdge(end: end + 2.5, time: time * 1.15 + 2, amplitude: 4.5).fill(fill.opacity(0.4))
                        surface.fill(fill)
                            .overlay(alignment: .leading) {
                                // Dimmed a little, so the light and the bubbles show on it.
                                Color.black.opacity(0.2)
                                LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .top, endPoint: .center)
                                ForEach(0..<9, id: \.self) { index in
                                    let bubble = Bubble(index: index, time: time)
                                    // It grows as it goes, wobbles across the bar, and fades in and out at the ends.
                                    Circle()
                                        .fill(.white.opacity(bubble.opacity))
                                        .frame(width: bubble.size)
                                        .offset(x: 22 + (end - 30) * bubble.travel, y: bubble.y)
                                        .frame(maxHeight: .infinity)
                                }
                            }
                            .mask { surface }
                    } else {
                        Capsule().fill(fill).frame(width: width)
                    }
                    Image(systemName: charging ? "bolt.fill" : "battery.100percent")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(width: height)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: height)
        .animation(spring, value: level)
    }
}

/// One bubble in the charging liquid at `time`. Its speed, size, height and wobble come from its index, so each
/// keeps its own.
private struct Bubble {
    let travel: Double
    let size: CGFloat
    let y: CGFloat
    let opacity: Double

    init(index: Int, time: Double) {
        let seed = Double(index) * 0.618
        func part(_ scale: Double) -> Double { (seed * scale).truncatingRemainder(dividingBy: 1) }
        travel = (time * (0.12 + 0.1 * part(5)) + seed).truncatingRemainder(dividingBy: 1)
        size = (2 + 3.5 * part(3)) * (0.7 + 0.5 * travel)
        y = part(7) * 14 - 7 + 2.2 * sin(time * (2 + 2 * part(11)) + seed * 9)
        opacity = min(1, 4 * travel) * min(1, 6 * (1 - travel))
    }
}

/// A bar filled from the left to about `end`, whose right edge is a rolling wave, like the surface of a liquid on its
/// side: a long swell with a shorter ripple running the other way over it.
nonisolated struct LiquidEdge: Shape {
    let end: CGFloat
    let time: Double
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        for y in stride(from: 0, through: rect.height, by: 0.5) {
            let across = Double(y) / Double(rect.height) * 2 * .pi
            let swell = sin(across * 0.9 + time * 2.4), ripple = 0.4 * sin(across * 2.3 - time * 3.7)
            path.addLine(to: CGPoint(x: end - amplitude + amplitude * (swell + ripple) / 1.4, y: y))
        }
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
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
