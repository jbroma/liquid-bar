import AppKit
import LiquidBarCore
import SwiftUI

/// The Control Center dropdown's state and actions. It reads the system when the dropdown opens and after each
/// change, and does nothing while the dropdown is closed.
@Observable
final class Controls {
    private(set) var state = ControlState()
    @ObservationIgnored private var readingBluetooth: Task<Void, Never>?

    func refresh() {
        let next = ControlState(brightness: DisplayBrightness.read(), keyboard: KeyboardBrightness.read(), bluetooth: state.bluetooth,
                                devices: state.devices, airDrop: AirDrop.mode(), darkMode: Appearance.isDark(), nightShift: NightShift.isOn())
        if next != state { state = next }
        // Until it lands, the tile shows what the last read found.
        guard readingBluetooth == nil else { return }
        readingBluetooth = Task {
            let (on, devices) = await Bluetooth.read()
            if on != state.bluetooth || devices != state.devices { (state.bluetooth, state.devices) = (on, devices) }
            readingBluetooth = nil
        }
    }

    func setBrightness(_ level: Int) {
        state.brightness = Double(level) / 100
        DisplayBrightness.write(Double(level) / 100)
    }

    func setKeyboard(_ level: Int) {
        state.keyboard = Double(level) / 100
        KeyboardBrightness.write(Double(level) / 100)
    }

    /// A tile's click. `dismiss` closes the dropdown first when the tile hands over to another window.
    func press(_ tile: ControlTile, dismiss: () -> Void) {
        haptic()
        switch tile {
        case .airDrop:
            dismiss()
            AirDrop.openWindow()
        case .screenMirroring:
            dismiss()
            if !SystemControlCenter.open(SystemControlCenter.screenMirroring) { openSettings("com.apple.Displays-Settings.extension") }
        case .screenshot:
            dismiss()
            shell("open -b com.apple.screenshot.launcher")
        case .darkMode:
            guard let dark = state.darkMode else { return openSettings("com.apple.Appearance-Settings.extension") }
            state.darkMode = !dark
            Appearance.setDark(!dark)
        case .nightShift:
            guard let on = state.nightShift else { return openSettings("com.apple.Displays-Settings.extension") }
            state.nightShift = !on
            NightShift.setOn(!on)
        case .bluetooth:
            guard let on = state.bluetooth, Bluetooth.canSwitch else { return openSettings("com.apple.BluetoothSettings") }
            state.bluetooth = !on
            Bluetooth.setOn(!on)
            refresh(after: .seconds(1.5))
        case .focus:
            break
        }
    }

    func toggle(_ device: BluetoothDevice) {
        haptic()
        Task {
            await Bluetooth.toggle(device.id)
            refresh()
        }
    }

    /// Reads again once a change the system makes in the background has landed.
    private func refresh(after delay: Duration) {
        Task {
            try? await Task.sleep(for: delay)
            refresh()
        }
    }

    /// The real Control Center, for anything the dropdown does not cover.
    func openSystemControlCenter() {
        if !SystemControlCenter.open(SystemControlCenter.controlCenter) {
            AppMenus.explainAccess("open Control Center", at: NSEvent.mouseLocation)
        }
    }
}

func openSettings(_ pane: String) {
    shell("open 'x-apple.systempreferences:\(pane)'")
}

/// Like Control Center, minus Wi-Fi, Sound and Now Playing, which have their own items: wide tiles with a status
/// line, round tiles, the brightness sliders, the paired Bluetooth devices, and a way into the real one.
struct ControlCenterMenu: View {
    let controls: Controls
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        let state = controls.state
        MenuBody {
            MenuTitle(title: "Control Center")
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                let wide = ControlTile.allCases.filter(\.isWide)
                ForEach(0..<wide.count / 2, id: \.self) { row in
                    GridRow {
                        ForEach(wide[row * 2...row * 2 + 1], id: \.self) { tile in
                            WideTile(tile: tile, on: tile.isOn(state), status: tile.status(state)) { controls.press(tile, dismiss: slot.dismiss) }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            HStack(spacing: 8) {
                ForEach(ControlTile.allCases.filter { !$0.isWide }, id: \.self) { tile in
                    RoundTile(tile: tile, on: tile.isOn(state)) { controls.press(tile, dismiss: slot.dismiss) }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            if let brightness = state.brightness {
                MenuSection(title: "Display")
                MenuRow { LevelSlider(level: percent(brightness), muted: false, symbol: "sun.max.fill", set: controls.setBrightness) }
            }
            if let keyboard = state.keyboard {
                MenuSection(title: "Keyboard Brightness")
                MenuRow { LevelSlider(level: percent(keyboard), muted: false, symbol: "light.max", set: controls.setKeyboard) }
            }
            if !state.devices.isEmpty {
                MenuSeparator()
                MenuSection(title: "Bluetooth Devices")
                ForEach(state.devices) { device in
                    MenuButton { controls.toggle(device) } content: {
                        DeviceIcon(symbol: device.symbol, selected: device.connected)
                        Text(device.name).lineLimit(1)
                        Spacer(minLength: 8)
                        if let battery = device.battery { Text("\(battery)%").foregroundStyle(secondary).monospacedDigit() }
                    }
                }
            }
            MenuSeparator()
            MenuButton {
                slot.dismiss()
                controls.openSystemControlCenter()
            } content: {
                Text("Control Center…").foregroundStyle(secondary)
            }
        }
        .task {
            controls.refresh()
            for await _ in DistributedNotificationCenter.default().notifications(named: .init("AppleInterfaceThemeChangedNotification")) {
                controls.refresh()
            }
        }
    }
}

private func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}

/// A tile's symbol in a circle, filled white while the control is on, like the output devices in the Sound menu.
private struct TileIcon: View {
    let tile: ControlTile
    let on: Bool
    var size: CGFloat = 28

    var body: some View {
        Group {
            switch tile {
            // SF Symbols has no Bluetooth rune.
            case .bluetooth: BluetoothRune().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: size * 0.3, height: size * 0.5)
            case .airDrop: Image(systemName: "dot.radiowaves.up.forward")
            case .focus: Image(systemName: "moon.fill")
            case .screenMirroring: Image(systemName: "rectangle.on.rectangle")
            case .darkMode: Image(systemName: "circle.lefthalf.filled")
            case .nightShift: Image(systemName: "sun.horizon.fill")
            case .screenshot: Image(systemName: "camera.viewfinder")
            }
        }
        .font(.system(size: size * 0.43, weight: .semibold))
        .foregroundStyle(on ? Color.black : Color.barWhite)
        .frame(width: size, height: size)
        .background(Circle().fill(on ? Color.barWhite : .white.opacity(0.14)))
    }
}

/// ᛒ: two stacked arrowheads on a vertical stroke.
private struct BluetoothRune: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        var path = Path()
        path.addLines([point(0, 0.27), point(1, 0.73), point(0.5, 1), point(0.5, 0), point(1, 0.27), point(0, 0.73)])
        return path
    }
}

private struct WideTile: View {
    let tile: ControlTile
    let on: Bool
    let status: String?
    let action: () -> Void

    var body: some View {
        TileButton(radius: 16, action: action) {
            HStack(spacing: 8) {
                TileIcon(tile: tile, on: on)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.title).font(.system(size: 12, weight: .semibold))
                    if let status { Text(status).font(.system(size: 11)).foregroundStyle(secondary) }
                }
                .lineLimit(status == nil ? 2 : 1)
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 50)
        }
    }
}

private struct RoundTile: View {
    let tile: ControlTile
    let on: Bool
    let action: () -> Void

    var body: some View {
        TileButton(radius: 16, action: action) {
            VStack(spacing: 4) {
                TileIcon(tile: tile, on: on, size: 30)
                Text(tile.title).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary).lineLimit(1)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
    }
}

/// A rounded glass tile, the pills' material, that lightens under the pointer and sinks while pressed.
private struct TileButton<Label: View>: View {
    let radius: CGFloat
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(TileStyle(radius: radius, hovering: hovering))
            .onHover { hovering = $0 }
    }
}

private struct TileStyle: ButtonStyle {
    let radius: CGFloat
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        configuration.label
            .contentShape(shape)
            .background(shape.fill(.white.opacity(configuration.isPressed ? 0.14 : hovering ? 0.08 : 0)))
            .glassEffect(.regular.interactive(), in: shape)
            .overlay { shape.strokeBorder(Specular.gradient, lineWidth: 0.5).allowsHitTesting(false) }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
