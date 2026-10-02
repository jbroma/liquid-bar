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
    /// Whether the Focus status item was there at the last look.
    @ObservationIgnored private var focusItem: Bool?

    /// Focus is read once, then followed through the notifications macOS posts under Do Not Disturb's old name up to
    /// macOS 26. They arrive as Focus switches. macOS 27 no longer posts them, so Focus also follows its status item.
    init() {
        readFocus()
        for (name, on) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.state.focus = on }
            }
        }
    }

    func readFocus() {
        focusItem = SystemControlCenter.focusIsOn()
        state.focus = focusItem
        SystemControlCenter.onItemsChanged { [weak self] in self?.followFocus() }
    }

    /// The status item leaves the menu bar only about 5s after Focus ends, so only its coming and going moves the tile:
    /// a read in between would undo a switch just made here.
    private func followFocus() {
        let shown = SystemControlCenter.focusIsOn()
        guard shown != focusItem else { return }
        (focusItem, state.focus) = (shown, shown)
    }

    func refresh() {
        let airDrop = AirDrop.mode()
        if let airDrop, airDrop != .off { lastAirDrop = airDrop }
        let next = ControlState(brightness: DisplayBrightness.read(), keyboard: KeyboardBrightness.read(), bluetooth: state.bluetooth,
                                devices: state.devices, focus: state.focus, airDrop: airDrop, darkMode: Appearance.isDark(), nightShift: NightShift.isOn(),
                                trueTone: TrueTone.isOn(), stageManager: StageManager.isOn())
        if next != state { state = next }
        // Until it lands, the tile shows what the last read found. Before the user allows Bluetooth, a read would ask.
        guard readingBluetooth == nil, Permission.bluetooth.status == .granted else { return }
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
        case .trueTone:
            guard let on = state.trueTone else { return openSettings("com.apple.Displays-Settings.extension") }
            state.trueTone = !on
            TrueTone.setOn(!on)
        case .stageManager:
            let on = state.stageManager ?? false
            state.stageManager = !on
            StageManager.setOn(!on)
        case .bluetooth:
            guard Permission.bluetooth.status == .granted else { return Permission.bluetooth.request() }
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

/// Like Control Center, with the items the config's `controlCenter` lists. Bluetooth and AirDrop are rows beside a
/// Focus tile, then come the sliders and the other controls as labeled tiles, with a hairline between the groups. The
/// Bluetooth and AirDrop rows unfold a list with the control's devices or modes.
struct ControlCenterMenu: View {
    let model: BarModel
    @Environment(ExpansionSlot.self) private var slot
    @State private var expanded: ControlTile?

    var body: some View {
        let controls = model.controls
        let state = controls.state
        let items = model.config.controlCenter
        let rows = items.compactMap(\.tile).filter { $0 == .bluetooth || $0 == .airDrop }
        // Focus is the tall tile beside the rows, and without them one of the tiles below.
        let strip = items.compactMap(\.tile).filter { !rows.contains($0) && ($0 != .focus || rows.isEmpty) }
        let sliders = sliders(items, controls, state)
        MenuBody {
            // Groups sit straight on the dropdown's glass, with a hairline between them, like the other dropdowns.
            VStack(spacing: 0) {
                if !rows.isEmpty {
                    switches(rows, focus: items.contains(.focus), controls, state)
                    if !sliders.isEmpty || !strip.isEmpty || expanded != nil { MenuSeparator() }
                }
                if let tile = expanded {
                    VStack(spacing: 0) {
                        expansion(tile, controls, state)
                        if !sliders.isEmpty || !strip.isEmpty { MenuSeparator() }
                    }
                    .transition(.opacity)
                }
                if !sliders.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(sliders, id: \.name) { slider in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(slider.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                LevelSlider(level: slider.level, muted: slider.muted, symbol: slider.symbol, height: 24, set: slider.set)
                                    .accessibilityLabel(slider.name)
                                    .accessibilityValue("\(slider.level)%")
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    if !strip.isEmpty { MenuSeparator() }
                }
                // At most four tiles to a line, and the lines about even: five are three and two.
                let perLine = max(1, Int((Double(strip.count) / (Double(strip.count) / 4).rounded(.up)).rounded(.up)))
                ForEach(Array(stride(from: 0, to: strip.count, by: perLine)), id: \.self) { start in
                    tiles(Array(strip[start ..< min(start + perLine, strip.count)]), controls, state)
                }
                if items.isEmpty {
                    MenuButton { delegate.settings.show(.controlCenter) } content: { Text("Choose Controls…") }
                }
            }
        }
        // SwiftUI can keep this view's state from one opening to the next; like Control Center, each opens collapsed.
        .onChange(of: slot.owner == .controlCenter) { _, open in if !open { expanded = nil } }
        .task {
            controls.refresh()
            for await _ in DistributedNotificationCenter.default().notifications(named: .init("AppleInterfaceThemeChangedNotification")) {
                controls.refresh()
            }
        }
    }

    private typealias SliderItem = (name: String, level: Int, muted: Bool, symbol: String, set: (Int) -> Void)

    /// The sliders that are on and whose level can be read.
    private func sliders(_ items: [ControlItem], _ controls: Controls, _ state: ControlState) -> [SliderItem] {
        items.compactMap { item in
            switch item {
            case .display: state.brightness.map { ("Display", percent($0), false, "sun.max.fill", controls.setBrightness) }
            case .keyboard: state.keyboard.map { ("Keyboard Brightness", percent($0), false, "light.max", controls.setKeyboard) }
            case .sound: ("Sound", model.volume.level, model.volume.muted, model.volume.symbol, model.setVolume)
            default: nil
            }
        }
    }

    /// Bluetooth and AirDrop beside a tall Focus tile, as at the top of macOS's Control Center. The open list comes in
    /// a group of its own below them, so no row moves under the pointer.
    private func switches(_ rows: [ControlTile], focus: Bool, _ controls: Controls, _ state: ControlState) -> some View {
        HStack(spacing: 8) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row($0, controls, state) }
            }
            .frame(maxWidth: .infinity)
            if focus {
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1).padding(.vertical, 8)
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
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ tile: ControlTile, _ controls: Controls, _ state: ControlState) -> some View {
        ControlRow(tile: tile, state: state, open: expanded == tile) {
            withAnimation(spring) { expanded = expanded == tile ? nil : tile }
        } toggle: {
            controls.press(tile, dismiss: slot.dismiss)
        }
    }

    private func tiles(_ strip: [ControlTile], _ controls: Controls, _ state: ControlState) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(strip, id: \.self) { tile in
                ControlButton(name: tile.name, radius: 12) { controls.press(tile, dismiss: slot.dismiss) } label: {
                    VStack(spacing: 4) {
                        TileIcon(tile: tile, on: tile.isOn(state), size: 34)
                        Text(tile.name).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder private func expansion(_ tile: ControlTile, _ controls: Controls, _ state: ControlState) -> some View {
        switch tile {
        case .bluetooth: bluetoothDevices(controls, state)
        case .airDrop: airDropModes(controls, state)
        default: EmptyView()
        }
    }

    /// The paired devices, dimmed while Bluetooth is off, and its settings. The circle on the Bluetooth row is the
    /// switch.
    @ViewBuilder private func bluetoothDevices(_ controls: Controls, _ state: ControlState) -> some View {
        if Permission.bluetooth.status != .granted {
            MenuButton { Permission.bluetooth.request() } content: { Text("Allow Bluetooth Access…") }.frame(minHeight: 30)
        } else if state.devices.isEmpty {
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

    /// Who can see this Mac while AirDrop is on. The circle on the AirDrop row is the switch.
    @ViewBuilder private func airDropModes(_ controls: Controls, _ state: ControlState) -> some View {
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
/// a chevron. The circle switches the control, as in Control Center; a click anywhere else unfolds its list. The row
/// lights up as one piece under the pointer and stays lit while its list is open.
private struct ControlRow: View {
    let tile: ControlTile
    let state: ControlState
    let open: Bool
    let expand: () -> Void
    let toggle: () -> Void

    var body: some View {
        ControlButton(name: tile.name, radius: 14, selected: open, action: expand) {
            HStack(spacing: 0) {
                CircleToggle(tile: tile, on: tile.isOn(state), action: toggle)
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

/// A row's circle as its own button, which grows a little under the pointer to show it does something else than the row.
private struct CircleToggle: View {
    let tile: ControlTile
    let on: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { TileIcon(tile: tile, on: on, size: 28) }
            .buttonStyle(.plain)
            .scaleEffect(hovering ? 1.1 : 1)
            .brightness(hovering ? 0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
            .accessibilityLabel(on ? "Turn \(tile.name) Off" : "Turn \(tile.name) On")
    }
}

/// A control's symbol in a circle, filled with the accent colour while the control is on, like the output devices in the Sound menu.
struct TileIcon: View {
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
            case .trueTone: Image(systemName: "sun.max.fill")
            case .stageManager: Image(systemName: "squares.leading.rectangle")
            case .screenshot: Image(systemName: "camera.viewfinder")
            }
        }
        .font(.system(size: size * 0.43, weight: .semibold))
        .iconCircle(on: on, size: size)
    }
}

/// ᛒ: two stacked arrowheads on a vertical stroke.
private nonisolated struct BluetoothRune: Shape {
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
