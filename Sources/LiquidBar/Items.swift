import CoreWLAN
import LiquidBarCore
import SwiftUI

/// The small grey first line of a two-line detail.
struct Caption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.barWhite.opacity(0.7))
            .lineLimit(1)
    }
}

/// A slim level bar, 0...1.
struct Meter: View {
    let value: Double
    var tint = Color.barWhite
    var width: CGFloat = 72

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.2))
            .frame(width: width, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: width * min(1, max(0, value)))
            }
    }
}

/// Scroll changes the level in steps of 2; the detail names the output device and shows the level.
struct VolumePill: View {
    let model: BarModel

    var body: some View {
        let volume = model.volume
        let level = volume.muted ? 0 : volume.level
        LivePill(pulse: volume) {
            Image(systemName: volume.symbol)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
        } detail: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Caption(text: volume.device)
                    Meter(value: Double(level) / 100)
                }
                .frame(minWidth: 72, alignment: .leading)
                Text("\(level)%")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, alignment: .trailing)
                    .contentTransition(.numericText(value: Double(level)))
            }
        }
        .animation(spring, value: level)
        .overlay {
            ScrollCatcher { steps in model.nudgeVolume(steps) }
        }
    }
}

/// Pulses on plug and unplug; the detail says how long the battery lasts or how long charging takes.
struct BatteryPill: View {
    let battery: BatteryState

    var body: some View {
        LivePill(pulse: battery.onAC) {
            HStack(spacing: 5) {
                Image(systemName: battery.symbol)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(battery.tint.color, Color.barWhite.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: battery.onAC)
                Text("\(battery.percent)%")
                    .font(.system(size: 12, weight: .bold))
                    .contentTransition(.numericText(value: Double(battery.percent)))
            }
        } detail: {
            VStack(alignment: .leading, spacing: 4) {
                Caption(text: battery.detail)
                Meter(value: Double(battery.percent) / 100, tint: battery.tint.color)
            }
        }
        .animation(spring, value: battery)
    }
}

/// Pulses when connectivity changes. The detail names the network and shows live throughput, sampled once a
/// second only while it is visible.
struct NetworkPill: View {
    let network: NetworkState

    var body: some View {
        LivePill(pulse: network.kind) {
            Image(systemName: network.symbol)
                .frame(width: 18)
                .contentTransition(.symbolEffect(.replace))
        } detail: {
            NetworkDetail(network: network)
        }
    }
}

private struct NetworkDetail: View {
    let network: NetworkState
    @State private var name: String?
    @State private var bars: Int?
    @State private var rates: (down: Double, up: Double)?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Caption(text: name ?? fallbackName)
                if name == nil, let bars {
                    Image(systemName: "wifi", variableValue: Double(bars) / 3)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.barWhite.opacity(0.7))
                }
            }
            if network.kind != .offline {
                Text("↓ \(throughputText(rates?.down ?? 0))   ↑ \(throughputText(rates?.up ?? 0))")
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
        .task(id: network) { await sample() }
    }

    private var fallbackName: String {
        switch network.kind {
        case .wifi: "Wi-Fi"
        case .wired: "Ethernet"
        case .offline: "Offline"
        }
    }

    private func sample() async {
        if network.kind == .wifi, let wifi = CWWiFiClient.shared().interface() {
            // The SSID needs Location access; without it CoreWLAN returns nil and signal bars stand in.
            name = wifi.ssid()
            bars = signalBars(rssi: wifi.rssiValue())
        } else {
            name = nil
            bars = nil
        }
        guard let interface = network.interface, var last = interfaceBytes(interface) else { return }
        var lastTime = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let now = interfaceBytes(interface) else { return }
            let elapsed = Date().timeIntervalSince(lastTime)
            withAnimation(spring) {
                rates = (Double(now.received &- last.received) / elapsed, Double(now.sent &- last.sent) / elapsed)
            }
            last = now
            lastTime = Date()
        }
    }
}
