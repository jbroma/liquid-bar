import LiquidBarCore
import SwiftUI

struct VolumeMenu: View {
    let model: BarModel

    var body: some View {
        MenuBody { MenuTitle(title: "Sound", accessory: "\(model.volume.level)%") }
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
