import CoreLocation
import CoreWLAN
import LiquidBarCore
import SwiftUI

/// Like the Wi-Fi menu extra: the Wi-Fi switch, the current network with its address and live throughput, then the
/// networks in range to join. Throughput is sampled once a second and the networks are scanned every 10 s, only while
/// the menu is open.
struct NetworkMenu: View {
    let network: NetworkState
    @State private var power: Bool?
    /// Why CoreWLAN refused to switch Wi-Fi, shown beside the disabled switch.
    @State private var failure: String?
    @State private var name: String?
    @State private var bars: Int?
    @State private var address: String?
    @State private var rates: (down: Double, up: Double)?
    @State private var scan: [WiFiNetwork] = []
    @State private var join = JoinState.idle
    /// The network list starts folded, like Menu Bar Items; it folds again each time the dropdown closes.
    @State private var listed = false
    @Environment(ExpansionSlot.self) private var slot
    private let location = LocationAccess.shared

    var body: some View {
        MenuBody {
            HeaderRow(title: "Wi-Fi") {
                if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(secondary).lineLimit(1).help(failure) }
                GlassSwitch(on: failure == nil ? power : nil, set: setPower)
            }
            if network.kind == .wired || (network.kind != .offline && power != false) {
                MenuSeparator()
                MenuRow {
                    DeviceIcon(symbol: network.symbol, selected: true)
                    Text(name ?? (network.kind == .wifi ? "Wi-Fi Network" : "Connected")).lineLimit(1)
                    Spacer(minLength: 8)
                    if let bars { Image(systemName: "wifi", variableValue: Double(bars) / 3).foregroundStyle(secondary) }
                }
                MenuSeparator()
                if let address { CopyableValue(title: "IP Address", value: address) } else { MenuValue(title: "IP Address", value: "None") }
                MenuValue(title: "Download", value: throughputText(rates?.down ?? 0))
                MenuValue(title: "Upload", value: throughputText(rates?.up ?? 0))
            }
            if power == true {
                MenuSeparator()
                if location.granted {
                    let networks = WiFiNetworks(scan: scan, current: name)
                    HeaderRow(title: "Networks", bold: false) {
                        Text("\(networks.known.count + networks.other.count)").foregroundStyle(secondary).monospacedDigit()
                        Disclosure(open: listed)
                    }
                    .hoverButton { withAnimation(spring) { listed.toggle() } }
                    if listed {
                        NetworkList(networks: networks, join: join, select: select, submit: submit) { join.cancel() }
                            .transition(.opacity)
                    }
                } else {
                    MenuButton { Permission.location.request() } content: {
                        Text(location.status == .notDetermined ? "Show Network Names…" : "Allow Location to see network names…").lineLimit(1)
                    }
                }
                // macOS has no public way to open its own "Join Other Network" dialog.
                MenuButton { openSettings("com.apple.wifi-settings-extension") } content: { Text("Other Network…") }
            }
            MenuSeparator()
            SettingsButton(title: "Network Settings…", pane: "com.apple.Network-Settings.extension")
        }
        .onChange(of: slot.owner == .wifi) { _, open in if !open { listed = false } }
        .task(id: network) { await sample() }
        .task(id: location.granted) {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func setPower(_ on: Bool) {
        power = on
        Task {
            failure = await blocking { () -> String? in
                do {
                    try CWWiFiClient.shared().interface()?.setPower(on)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }
            power = CWWiFiClient.shared().interface()?.powerOn()
            await refresh()
        }
    }

    private func select(_ network: WiFiNetwork) {
        if let request = join.select(network) { start(request) }
    }

    private func submit(_ password: String) {
        if let request = join.submit(password) { start(request) }
    }

    private func start(_ request: JoinRequest) {
        Task {
            join.finish(error: await blocking { joinNetwork(request) })
            await refresh()
        }
    }

    private func readCurrent() {
        let wifi = network.kind == .wifi ? CWWiFiClient.shared().interface() : nil
        name = wifi?.ssid()
        bars = wifi.map { signalBars(rssi: $0.rssiValue()) }
    }

    /// The current network, and the networks in range.
    private func refresh() async {
        readCurrent()
        guard location.granted else { return }
        if scan.isEmpty, let cached = scanNetworks(cached: true) { scan = cached }
        if let found = await blocking({ scanNetworks(cached: false) }) { scan = found }
    }

    private func sample() async {
        power = CWWiFiClient.shared().interface()?.powerOn()
        address = network.interface.flatMap(ipv4Address)
        readCurrent()
        guard let interface = network.interface, var last = interfaceBytes(interface) else { return }
        var lastTime = Date()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let now = interfaceBytes(interface) else { return }
            let elapsed = Date().timeIntervalSince(lastTime)
            rates = (Double(now.received &- last.received) / elapsed, Double(now.sent &- last.sent) / elapsed)
            last = now
            lastTime = Date()
        }
    }
}

/// "Known Networks" and "Other Networks", each row with its signal and a lock when secured. Past about eight rows the
/// list scrolls.
private struct NetworkList: View {
    let networks: WiFiNetworks
    let join: JoinState
    let select: (WiFiNetwork) -> Void
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("Known Networks", networks.known)
                section("Other Networks", networks.other)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(height, 250))
    }

    @ViewBuilder private func section(_ title: String, _ list: [WiFiNetwork]) -> some View {
        if !list.isEmpty {
            MenuSection(title: title)
            ForEach(list) { row($0) }
        }
    }

    @ViewBuilder private func row(_ network: WiFiNetwork) -> some View {
        MenuButton { select(network) } content: {
            DeviceIcon(symbol: "wifi", selected: false, level: Double(network.bars) / 3)
            Text(network.ssid).lineLimit(1)
            Spacer(minLength: 8)
            if case .joining(network.ssid, _) = join {
                ProgressView().controlSize(.small)
            } else if network.secured {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(secondary)
            }
        }
        switch join {
        case .password(network.ssid, let error): PasswordField(error: error, submit: submit, cancel: cancel)
        case .failed(network.ssid, let error): ErrorText(error: error).padding(.horizontal, 8)
        default: EmptyView()
        }
    }
}

/// A new network's password, typed straight into the dropdown. Return joins, Esc folds the row.
private struct PasswordField: View {
    let error: String?
    let submit: (String) -> Void
    let cancel: () -> Void
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { submit(password) }
                    .onExitCommand(perform: cancel)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.1)))
                Text("Join")
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(password.isEmpty ? 0.4 : 1)))
                    .hoverButton { submit(password) }
            }
            if let error { ErrorText(error: error) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(KeyWindow())
        .onAppear { focused = true }
    }
}

private struct ErrorText: View {
    let error: String

    var body: some View {
        Text(error).font(.system(size: 11)).foregroundStyle(secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
    }
}

/// Makes the dropdown the key window while shown, so a field in it takes typing without activating the bar.
private struct KeyWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Grab() }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Grab: NSView {
        override func viewDidMoveToWindow() {
            window?.makeKey()
        }

        // A panel that stays key keeps the keyboard from the front app even once the field is gone; only ordering it
        // out hands the keyboard back.
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            guard newWindow == nil, let window, window.isKeyWindow, let parent = window.parent else { return }
            window.orderOut(nil)
            parent.addChildWindow(window, ordered: .above)
        }
    }
}

/// Location access, without which CoreWLAN hides network names. Asked for only from a click on the Wi-Fi dropdown's
/// row or the Settings window, never by opening the dropdown, which a network change can do on its own.
@Observable
final class LocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAccess()
    private(set) var status = CLAuthorizationStatus.notDetermined
    @ObservationIgnored private let manager = CLLocationManager()

    var granted: Bool { status == .authorizedAlways }

    override init() {
        super.init()
        manager.delegate = self
        status = manager.authorizationStatus
    }

    func request() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { self.status = status }
    }
}

/// The networks in range, or nil when the scan failed. A new scan blocks for several seconds; the cached results of
/// the last one, by any app, return at once.
nonisolated func scanNetworks(cached: Bool) -> [WiFiNetwork]? {
    guard let interface = CWWiFiClient.shared().interface(), interface.powerOn(),
          let found = cached ? interface.cachedScanResults() : try? interface.scanForNetworks(withName: nil)
    else { return nil }
    let known = Set((interface.configuration()?.networkProfiles.array ?? []).compactMap { ($0 as? CWNetworkProfile)?.ssid })
    return found.compactMap { network in
        network.ssid.map { WiFiNetwork(ssid: $0, rssi: network.rssiValue, secured: !network.supportsSecurity(.none), known: known.contains($0)) }
    }
}

/// Joins a network by name, and returns why it failed. Blocks until the Mac is on the network or gives up.
nonisolated func joinNetwork(_ request: JoinRequest) -> String? {
    guard let interface = CWWiFiClient.shared().interface() else { return "Wi-Fi is unavailable." }
    do {
        guard let target = try interface.scanForNetworks(withName: request.ssid).max(by: { $0.rssiValue < $1.rssiValue }) else {
            return "\(request.ssid) is out of range."
        }
        var password = request.password
        // CoreWLAN does not use the saved password by itself. It lives in the System keychain, which asks the user
        // for an administrator password before handing it over.
        if password == nil, !target.supportsSecurity(.none) {
            var saved: NSString?
            guard CWKeychainFindWiFiPassword(.system, Data(request.ssid.utf8), &saved) == errSecSuccess, let saved else {
                return "Enter the password to join."
            }
            password = saved as String
        }
        try interface.associate(to: target, password: password)
        return nil
    } catch {
        return error.localizedDescription
    }
}
