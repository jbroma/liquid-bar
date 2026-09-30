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

/// Like Control Center, minus Wi-Fi, Sound and Now Playing, which have their own items. Bluetooth, AirDrop and Focus
/// come first, then the brightness sliders and a row of labeled tiles, each in its own module. The Bluetooth and AirDrop
/// rows unfold a module with the control's switch and its devices or modes. Then the other apps' status items the bar
/// covers.
struct ControlCenterMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot
    @State private var expanded: ControlTile?

    private static let strip: [ControlTile] = [.darkMode, .nightShift, .screenshot]

    var body: some View {
        let controls = model.controls
        let state = controls.state
        MenuBody {
            VStack(spacing: 8) {
                switches(controls, state)
                BrightnessModule(state: state, controls: controls)
                tiles(controls, state)
                MenuExtrasSection(model: model)
            }
        }
        // SwiftUI can keep this view's state from one opening to the next; like Control Center, each opens collapsed.
        .onChange(of: slot.owner == .controlCenter) { _, open in if !open { expanded = nil } }
        .task {
            MenuExtras.refresh(model)
            controls.refresh()
            for await _ in DistributedNotificationCenter.default().notifications(named: .init("AppleInterfaceThemeChangedNotification")) {
                controls.refresh()
            }
        }
    }

    /// Bluetooth and AirDrop beside a tall Focus tile, as at the top of macOS's Control Center, and the open list in a
    /// module of its own below them, so no row moves under the pointer.
    @ViewBuilder private func switches(_ controls: Controls, _ state: ControlState) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                row(.bluetooth, state)
                row(.airDrop, state)
            }
            .frame(maxWidth: .infinity)
            .module()
            ControlButton(name: ControlTile.focus.name, radius: 12) { controls.press(.focus, dismiss: slot.dismiss) } label: {
                VStack(spacing: 6) {
                    TileIcon(tile: .focus, on: ControlTile.focus.isOn(state), size: 34)
                    VStack(spacing: 0) {
                        Text(ControlTile.focus.name).font(.system(size: 12, weight: .semibold))
                        if let detail = ControlTile.focus.detail(state) { Text(detail).font(.system(size: 11)).foregroundStyle(secondary) }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .module()
        }
        .fixedSize(horizontal: false, vertical: true)
        if let tile = expanded {
            VStack(spacing: 0) { expansion(tile, controls, state) }
                .module()
                .transition(.opacity)
        }
    }

    private func row(_ tile: ControlTile, _ state: ControlState) -> some View {
        ControlRow(tile: tile, state: state, open: expanded == tile) {
            withAnimation(spring) { expanded = expanded == tile ? nil : tile }
        }
    }

    private func tiles(_ controls: Controls, _ state: ControlState) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.strip, id: \.self) { tile in
                ControlButton(name: tile.name, radius: 12) { controls.press(tile, dismiss: slot.dismiss) } label: {
                    VStack(spacing: 4) {
                        TileIcon(tile: tile, on: tile.isOn(state), size: 34)
                        Text(tile.name).font(.system(size: 11)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .module()
    }

    @ViewBuilder private func expansion(_ tile: ControlTile, _ controls: Controls, _ state: ControlState) -> some View {
        switch tile {
        case .bluetooth: bluetoothDevices(controls, state)
        case .airDrop: airDropModes(controls, state)
        default: EmptyView()
        }
    }

    /// Like the Bluetooth module of macOS's Control Center: its switch, the paired devices, dimmed while Bluetooth is
    /// off, and its settings.
    @ViewBuilder private func bluetoothDevices(_ controls: Controls, _ state: ControlState) -> some View {
        HeaderRow(title: "Bluetooth") {
            GlassSwitch(on: Bluetooth.canSwitch ? state.bluetooth : nil) { _ in controls.press(.bluetooth, dismiss: slot.dismiss) }
        }
        MenuSeparator()
        if state.devices.isEmpty {
            MenuRow { Text("No Devices").foregroundStyle(secondary) }.frame(minHeight: 30)
        }
        ForEach(state.devices) { device in
            ChoiceRow(symbol: device.symbol, title: device.name, selected: device.connected, detail: device.battery.map { "\($0)%" }) {
                controls.toggle(device)
            }
            .accessibilityValue(device.connected ? "Connected" : "Not Connected")
        }
        .opacity(state.bluetooth == true ? 1 : 0.45)
        .allowsHitTesting(state.bluetooth == true)
        MenuSeparator()
        SettingsButton(title: "Bluetooth Settings…", pane: "com.apple.BluetoothSettings")
    }

    /// Like the AirDrop module of macOS's Control Center: its switch, and who can see this Mac while it is on.
    @ViewBuilder private func airDropModes(_ controls: Controls, _ state: ControlState) -> some View {
        HeaderRow(title: "AirDrop") {
            GlassSwitch(on: state.airDrop.map { $0 != .off }) { _ in controls.press(.airDrop, dismiss: slot.dismiss) }
        }
        MenuSeparator()
        ForEach([AirDropMode.contactsOnly, .everyone], id: \.self) { mode in
            ChoiceRow(symbol: mode == .everyone ? "person.2.fill" : "person.crop.circle", title: mode.rawValue, selected: state.airDrop == mode) {
                controls.setAirDrop(mode)
            }
            .accessibilityAddTraits(state.airDrop == mode ? .isSelected : [])
        }
        MenuSeparator()
        SettingsButton(title: "AirDrop Settings…", pane: "com.apple.AirDrop-Handoff-Settings.extension")
    }
}

/// One of a module's choices: its symbol's circle fills with the accent colour while it is the current one.
private struct ChoiceRow: View {
    let symbol: String
    let title: String
    let selected: Bool
    var detail: String?
    let action: () -> Void

    var body: some View {
        MenuButton(action: action) {
            DeviceIcon(symbol: symbol, selected: selected, size: 26)
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            if let detail { Text(detail).foregroundStyle(secondary).monospacedDigit() }
        }
    }
}

private func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}

/// A control with choices as one row: its circle, filled with the accent colour while on, its name over its state, and
/// a chevron. A click unfolds its list, whose header holds the switch; the row stays lit while its list is open.
private struct ControlRow: View {
    let tile: ControlTile
    let state: ControlState
    let open: Bool
    let expand: () -> Void

    var body: some View {
        ControlButton(name: tile.name, radius: 14, selected: open, action: expand) {
            HStack(spacing: 0) {
                TileIcon(tile: tile, on: tile.isOn(state), size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tile.name).font(.system(size: 12, weight: .semibold))
                    if let detail = tile.detail(state) { Text(detail).font(.system(size: 11)).foregroundStyle(secondary) }
                }
                .lineLimit(1)
                .padding(.leading, 8)
                Spacer(minLength: 2)
                Disclosure(open: open)
            }
            .padding(5)
            .padding(.trailing, 2)
        }
        .accessibilityValue(tile.detail(state) ?? "")
    }
}

/// Display and keyboard brightness as labeled horizontal sliders. A slider whose level cannot be read is left out.
private struct BrightnessModule: View {
    let state: ControlState
    let controls: Controls

    var body: some View {
        if state.brightness != nil || state.keyboard != nil {
            VStack(spacing: 8) {
                if let level = state.brightness { slider("Display", level, "sun.max.fill", controls.setBrightness) }
                if let level = state.keyboard { slider("Keyboard", level, "light.max", controls.setKeyboard) }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .module()
        }
    }

    private func slider(_ name: String, _ level: Double, _ symbol: String, _ set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            LevelSlider(level: percent(level), muted: false, symbol: symbol, height: 24, set: set)
                .accessibilityLabel("\(name) Brightness")
                .accessibilityValue("\(percent(level))%")
        }
    }
}

extension View {
    /// The rounded panel behind a group of controls.
    func module() -> some View {
        padding(6).background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.1)))
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
    var selected = false
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .help(name)
            .accessibilityLabel(name)
            .buttonStyle(ControlStyle(radius: radius, hovering: hovering, selected: selected))
            .onHover { hovering = $0 }
    }
}

private struct ControlStyle: ButtonStyle {
    let radius: CGFloat
    let hovering: Bool
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .contentShape(shape)
            .background(shape.fill(.white.opacity(configuration.isPressed ? 0.14 : (hovering ? 0.06 : 0) + (selected ? 0.08 : 0))))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(spring, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(spring, value: selected)
    }
}
