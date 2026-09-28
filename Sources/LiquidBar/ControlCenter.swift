import AppKit
import LiquidBarCore
import SwiftUI

/// The Control Center dropdown's state and actions. It reads the system when the dropdown opens and after each
/// change, and apart from following Focus, does nothing while the dropdown is closed.
@Observable
final class Controls {
    private(set) var state = ControlState()
    @ObservationIgnored private var readingBluetooth: Task<Void, Never>?
    @ObservationIgnored private var togglingFocus = false
    @ObservationIgnored private var lastAirDrop: AirDropMode?

    /// Focus is read once, then followed through the notifications macOS still posts under Do Not Disturb's old name.
    /// They arrive as Focus switches, while its status item leaves the menu bar only about 5s after Focus ends.
    init() {
        state.focus = SystemControlCenter.focusIsOn()
        for (name, on) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.focus = on }
            }
        }
    }

    func refresh() {
        let airDrop = AirDrop.mode()
        if let airDrop, airDrop != .off { lastAirDrop = airDrop }
        let next = ControlState(brightness: DisplayBrightness.read(), keyboard: KeyboardBrightness.read(), bluetooth: state.bluetooth,
                                devices: state.devices, focus: state.focus, airDrop: airDrop, darkMode: Appearance.isDark(), nightShift: NightShift.isOn())
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

    func setAirDrop(_ mode: AirDropMode) {
        state.airDrop = mode
        if mode != .off { lastAirDrop = mode }
        Task {
            await blocking { AirDrop.set(mode) }
            refresh()
        }
    }

    /// A tile's click, on its circle for the tiles that expand. `dismiss` closes the dropdown first when the tile hands
    /// over to another window or a system banner.
    func press(_ tile: ControlTile, dismiss: () -> Void) {
        haptic()
        switch tile {
        case .airDrop:
            guard let airDrop = state.airDrop else { return openSettings("com.apple.AirDrop-Handoff-Settings.extension") }
            setAirDrop(airDrop.toggled(last: lastAirDrop))
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
            // Without the shortcut a toggle drives Control Center for about 3s; a second click would press into its panel.
            guard !togglingFocus else { return }
            togglingFocus = true
            // macOS answers every Focus change with a banner right where the dropdown hangs.
            dismiss()
            state.focus = !on
            Task {
                if await !blocking({ SystemControlCenter.toggleFocus() }) { state.focus = on }
                togglingFocus = false
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

/// Like Control Center, minus Wi-Fi, Sound and Now Playing, which have their own items. The switches with a state
/// worth reading (Bluetooth, AirDrop, Focus) are rows in one module beside tall brightness sliders; the rest are a strip
/// of circles. The Bluetooth and AirDrop rows unfold their devices and modes below the module, and the circle beside
/// each toggles the control. The strip is Dark Mode, Night Shift and Screenshot. Then the other apps' status items the
/// bar covers.
struct ControlCenterMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot
    @State private var expanded: ControlTile?

    private static let rows: [ControlTile] = [.bluetooth, .airDrop, .focus]
    private static let strip: [ControlTile] = [.darkMode, .nightShift, .screenshot]

    var body: some View {
        let controls = model.controls
        let state = controls.state
        MenuBody {
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Self.rows, id: \.self) { tile in
                        ControlRow(tile: tile, state: state, open: expanded == tile) {
                            controls.press(tile, dismiss: slot.dismiss)
                        } expand: {
                            withAnimation(spring) { expanded = expanded == tile ? nil : tile }
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
                if let brightness = state.brightness {
                    TallSlider(level: percent(brightness), symbol: "sun.max.fill", name: "Display Brightness", set: controls.setBrightness)
                }
                if let keyboard = state.keyboard {
                    TallSlider(level: percent(keyboard), symbol: "light.max", name: "Keyboard Brightness", set: controls.setKeyboard)
                }
            }
            // The sliders have no height of their own; this sizes them to the rows.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
            .padding(.top, 2)
            if let tile = expanded {
                VStack(spacing: 0) {
                    MenuSeparator()
                    switch tile {
                    case .bluetooth: bluetoothDevices(controls, state)
                    case .airDrop: airDropModes(controls, state)
                    default: EmptyView()
                    }
                    MenuSeparator()
                }
                .transition(.opacity)
            }
            HStack(spacing: 0) {
                ForEach(Self.strip, id: \.self) { tile in
                    ControlButton(name: tile.name, radius: 12) { controls.press(tile, dismiss: slot.dismiss) } label: {
                        TileIcon(tile: tile, on: tile.isOn(state), size: 32)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3)
                    }
                }
            }
            .padding(6)
            MenuExtrasSection(model: model)
        }
        .task {
            MenuExtras.refresh(model)
            controls.refresh()
            for await _ in DistributedNotificationCenter.default().notifications(named: .init("AppleInterfaceThemeChangedNotification")) {
                controls.refresh()
            }
        }
    }

    @ViewBuilder private func bluetoothDevices(_ controls: Controls, _ state: ControlState) -> some View {
        ForEach(state.devices) { device in
            MenuButton { controls.toggle(device) } content: {
                DeviceIcon(symbol: device.symbol, selected: device.connected, size: 20)
                Text(device.name).lineLimit(1)
                Spacer(minLength: 8)
                if let battery = device.battery { Text("\(battery)%").foregroundStyle(secondary).monospacedDigit() }
            }
            .accessibilityValue(device.connected ? "Connected" : "Not Connected")
        }
        MenuSeparator()
        SettingsButton(title: "Bluetooth Settings…", pane: "com.apple.BluetoothSettings")
    }

    @ViewBuilder private func airDropModes(_ controls: Controls, _ state: ControlState) -> some View {
        ForEach(AirDropMode.allCases, id: \.self) { mode in
            MenuButton { controls.setAirDrop(mode) } content: {
                Text(mode.rawValue).lineLimit(1)
                Spacer()
                if state.airDrop == mode { Image(systemName: "checkmark").fontWeight(.semibold) }
            }
        }
        MenuSeparator()
        SettingsButton(title: "AirDrop Settings…", pane: "com.apple.AirDrop-Handoff-Settings.extension")
    }
}

private func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}

/// A switch as a row: its circle, filled with the accent colour while on, then its name over its state. A tile that
/// expands splits the row in two targets, the circle toggling it and the rest unfolding its list.
private struct ControlRow: View {
    let tile: ControlTile
    let state: ControlState
    let open: Bool
    let press: () -> Void
    let expand: () -> Void

    private var icon: some View { TileIcon(tile: tile, on: tile.isOn(state), size: 28) }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tile.name).font(.system(size: 12, weight: .semibold))
            if let detail = tile.detail(state) { Text(detail).font(.system(size: 11)).foregroundStyle(secondary) }
        }
        .lineLimit(1)
    }

    var body: some View {
        if tile.expands {
            HStack(spacing: 0) {
                ControlButton(name: tile.name, radius: 14, action: press) { icon.padding(5) }
                ControlButton(name: "\(tile.name) Options", radius: 14, action: expand) {
                    HStack(spacing: 2) {
                        text
                        Spacer(minLength: 0)
                        Disclosure(open: open)
                    }
                    .padding(.vertical, 5)
                    .padding(.leading, 3)
                    .padding(.trailing, 7)
                }
            }
        } else {
            ControlButton(name: tile.name, radius: 14, action: press) {
                HStack(spacing: 8) {
                    icon
                    text
                    Spacer(minLength: 0)
                }
                .padding(5)
            }
        }
    }
}

/// A brightness slider standing upright, filled from the bottom. Click or drag anywhere sets the level.
private struct TallSlider: View {
    let level: Int
    let symbol: String
    let name: String
    let set: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let knob = proxy.size.width
            let travel = proxy.size.height - knob
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            ZStack(alignment: .bottom) {
                shape.fill(.white.opacity(0.14))
                shape.fill(.white).frame(height: knob + travel * CGFloat(level) / 100)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.6))
                    .frame(height: knob)
            }
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 0).onChanged { set(VolumeState.level(at: proxy.size.height - $0.location.y - knob / 2, width: travel)) })
        }
        .frame(width: 44)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityValue("\(level)%")
    }
}

/// A control's symbol in a circle, filled with the accent colour while the control is on, like the output devices in the Sound menu.
private struct TileIcon: View {
    let tile: ControlTile
    let on: Bool
    let size: CGFloat

    var body: some View {
        Group {
            switch tile {
            // SF Symbols has no Bluetooth rune.
            case .bluetooth: BluetoothRune().stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: size * 0.3, height: size * 0.5)
            case .airDrop: Image(systemName: "dot.radiowaves.up.forward")
            case .focus: Image(systemName: "moon.fill")
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

/// A control's click target, named by its tooltip. Its rounded area lightens under the pointer and dims while pressed.
private struct ControlButton<Label: View>: View {
    let name: String
    let radius: CGFloat
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .help(name)
            .accessibilityLabel(name)
            .buttonStyle(ControlStyle(radius: radius, hovering: hovering))
            .onHover { hovering = $0 }
    }
}

private struct ControlStyle: ButtonStyle {
    let radius: CGFloat
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .contentShape(shape)
            .background(shape.fill(.white.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
