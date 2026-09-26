import CoreAudio
import LiquidBarCore
import SwiftUI

/// Like the Sound menu extra: the level, mute, the output devices with the current one marked, and the settings pane.
struct VolumeMenu: View {
    let model: BarModel
    @State private var devices: [OutputDevice] = []
    @State private var current: AudioObjectID = 0

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
            .foregroundStyle(selected ? Color.black : Color.barWhite)
            .frame(width: 24, height: 24)
            .background(Circle().fill(selected ? Color.barWhite : .white.opacity(0.14)))
            .padding(.vertical, 2)
    }
}

struct NetworkMenu: View {
    let network: NetworkState

    var body: some View {
        MenuBody { MenuTitle(title: "Wi-Fi") }
    }
}

struct BatteryMenu: View {
    let battery: BatteryState?

    var body: some View {
        MenuBody { MenuTitle(title: "Battery", accessory: battery.map { "\($0.percent)%" }) }
    }
}

struct ClockMenu: View {
    let now: Date

    var body: some View {
        MenuBody { MenuTitle(title: longDateText(now)) }
    }
}

struct NowPlayingMenu: View {
    let nowPlaying: NowPlaying?
    let artwork: NSImage?
    let control: (String) -> Void

    var body: some View {
        MenuBody { MenuTitle(title: nowPlaying?.title ?? "") }
    }
}
