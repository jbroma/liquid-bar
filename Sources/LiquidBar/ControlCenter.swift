import AppKit
import LiquidBarCore
import SwiftUI

/// The Control Center dropdown's state and actions. It reads the system when the dropdown opens and after each
/// change, and does nothing while the dropdown is closed.
@Observable
final class Controls {
    private(set) var state = ControlState()
    @ObservationIgnored private var readingBluetooth: Task<Void, Never>?
    /// What the last toggle set Focus to. Its status item leaves the menu bar about 5s after Focus ends, so for a
    /// while this wins over it.
    @ObservationIgnored private var focusSet: (on: Bool, time: Date)?
    @ObservationIgnored private var togglingFocus = false

    func refresh() {
        let focus = focusSet.flatMap { $0.time.timeIntervalSinceNow > -8 ? $0.on : nil } ?? SystemControlCenter.focusIsOn()
        let next = ControlState(brightness: DisplayBrightness.read(), keyboard: KeyboardBrightness.read(), bluetooth: state.bluetooth,
                                devices: state.devices, focus: focus, airDrop: AirDrop.mode(), darkMode: Appearance.isDark(), nightShift: NightShift.isOn())
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
            shell("open -b com.apple.finder.Open-AirDrop")
        case .screenMirroring:
            dismiss()
            showControlCenterModule("controlcenter-screen-mirroring", else: "com.apple.Displays-Settings.extension")
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
            // The controller takes a moment to power up or down.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                refresh()
            }
        case .focus:
            guard let on = state.focus else { return openSettings("com.apple.Focus-Settings.extension") }
            // A toggle drives Control Center for about 3s; a second click meanwhile would press into the same panel.
            guard !togglingFocus else { return }
            togglingFocus = true
            state.focus = !on
            Task {
                if let now = await blocking({ SystemControlCenter.toggleFocus() }) { focusSet = (now, Date()) }
                togglingFocus = false
                refresh()
            }
        }
    }

    func toggle(_ device: BluetoothDevice) {
        haptic()
        Task {
            await Bluetooth.toggle(device.id)
            refresh()
        }
    }
}

/// Opens a module of the real Control Center off the main thread, or the settings pane when it cannot.
func showControlCenterModule(_ id: String, else pane: String) {
    Task {
        if await !blocking({ SystemControlCenter.showModule(id) }) { openSettings(pane) }
    }
}

func openSettings(_ pane: String) {
    shell("open 'x-apple.systempreferences:\(pane)'")
}

/// Like Control Center, minus Wi-Fi, Sound and Now Playing, which have their own items: a grid of the controls with a
/// way into the real one in its spare slot, the brightness sliders, the paired Bluetooth devices, and the other apps'
/// status items the bar covers.
struct ControlCenterMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot

    var body: some View {
        let controls = model.controls
        let state = controls.state
        MenuBody {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(ControlTile.allCases.prefix(4), id: \.self) { tile in
                        CircleTile(tile: tile, label: tile.label(state), on: tile.isOn(state)) { controls.press(tile, dismiss: slot.dismiss) }
                    }
                }
                GridRow {
                    ForEach(ControlTile.allCases.dropFirst(4), id: \.self) { tile in
                        CircleTile(tile: tile, label: tile.label(state), on: tile.isOn(state)) { controls.press(tile, dismiss: slot.dismiss) }
                    }
                    CircleTile(tile: nil, label: "More", on: false) {
                        slot.dismiss()
                        if let item = SystemControlCenter.extras()[SystemControlCenter.controlCenter] {
                            AX.pressLater(item)
                        } else {
                            AppMenus.explainAccess("open Control Center", at: NSEvent.mouseLocation)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.1)))
            .padding(.horizontal, 6)
            .padding(.top, 2)
            VStack(spacing: 4) {
                if let brightness = state.brightness { LevelSlider(level: percent(brightness), muted: false, symbol: "sun.max.fill", height: 18, set: controls.setBrightness) }
                if let keyboard = state.keyboard { LevelSlider(level: percent(keyboard), muted: false, symbol: "light.max", height: 18, set: controls.setKeyboard) }
            }
            .padding(6)
            if !state.devices.isEmpty {
                MenuSeparator()
                MenuSection(title: "Bluetooth Devices")
                ForEach(state.devices) { device in
                    MenuButton { controls.toggle(device) } content: {
                        DeviceIcon(symbol: device.symbol, selected: device.connected, size: 20)
                        Text(device.name).lineLimit(1)
                        Spacer(minLength: 8)
                        if let battery = device.battery { Text("\(battery)%").foregroundStyle(secondary).monospacedDigit() }
                    }
                }
            }
            MenuExtrasSection(extras: model.menuExtras)
        }
        .task {
            MenuExtras.refresh(model)
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

/// A tile's symbol in a circle, filled white while the control is on, like the output devices in the Sound menu. No
/// tile is the one that opens the real Control Center.
private struct TileIcon: View {
    let tile: ControlTile?
    let on: Bool
    let size: CGFloat

    var body: some View {
        Group {
            switch tile {
            case nil: Image(systemName: "ellipsis")
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
        .iconCircle(on: on, size: size)
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

/// A control's circle over its label. Its rounded area lightens under the pointer.
private struct CircleTile: View {
    let tile: ControlTile?
    let label: String
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                TileIcon(tile: tile, on: on, size: 32)
                Text(label).font(.system(size: 10, weight: .medium)).lineLimit(1)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TileStyle(hovering: hovering))
        .onHover { hovering = $0 }
    }
}

private struct TileStyle: ButtonStyle {
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        configuration.label
            .contentShape(shape)
            .background(shape.fill(.white.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
