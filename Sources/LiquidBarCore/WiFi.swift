/// A network a Wi-Fi scan found, by name.
public struct WiFiNetwork: Equatable, Hashable, Sendable, Identifiable {
    public var ssid: String
    /// Signal strength in dBm.
    public var rssi: Int
    public var secured: Bool
    /// This Mac has joined it before and keeps its settings.
    public var known: Bool

    public init(ssid: String, rssi: Int, secured: Bool, known: Bool) {
        self.ssid = ssid
        self.rssi = rssi
        self.secured = secured
        self.known = known
    }

    public var id: String { ssid }
    public var bars: Int { signalBars(rssi: rssi) }
}

/// The Wi-Fi dropdown's two lists, each strongest first, without the current network. A scan reports every access
/// point, so a name seen several times keeps its strongest signal.
public struct WiFiNetworks: Equatable, Sendable {
    public var known: [WiFiNetwork]
    public var other: [WiFiNetwork]

    public init(scan: [WiFiNetwork], current: String?) {
        let named = scan.filter { !$0.ssid.isEmpty && $0.ssid != current }
        let strongest = Dictionary(named.map { ($0.ssid, $0) }) { $0.rssi >= $1.rssi ? $0 : $1 }
        let sorted = strongest.values.sorted { $0.rssi != $1.rssi ? $0.rssi > $1.rssi : $0.ssid < $1.ssid }
        known = sorted.filter(\.known)
        other = sorted.filter { !$0.known }
    }
}

/// What the dropdown asks CoreWLAN to do. Without a password, a secured network's saved password is looked up.
public struct JoinRequest: Equatable, Sendable {
    public var ssid: String
    public var password: String?

    public init(ssid: String, password: String?) {
        self.ssid = ssid
        self.password = password
    }
}

/// Joining a network from the Wi-Fi dropdown, one at a time.
public enum JoinState: Equatable, Sendable {
    case idle
    /// The network's row shows a password field, with why the last attempt failed.
    case password(ssid: String, error: String?)
    case joining(ssid: String, secured: Bool)
    /// Joining an open network failed.
    case failed(ssid: String, error: String)

    /// A click on a network's row. A new secured network asks for its password, and a second click folds the field.
    public mutating func select(_ network: WiFiNetwork) -> JoinRequest? {
        if case .joining = self { return nil }
        if case .password(network.ssid, _) = self {
            self = .idle
            return nil
        }
        if network.secured && !network.known {
            self = .password(ssid: network.ssid, error: nil)
            return nil
        }
        self = .joining(ssid: network.ssid, secured: network.secured)
        return JoinRequest(ssid: network.ssid, password: nil)
    }

    public mutating func submit(_ password: String) -> JoinRequest? {
        guard case .password(let ssid, _) = self, !password.isEmpty else { return nil }
        self = .joining(ssid: ssid, secured: true)
        return JoinRequest(ssid: ssid, password: password)
    }

    public mutating func cancel() {
        if case .joining = self { return }
        self = .idle
    }

    /// The attempt ended, with CoreWLAN's reason when it failed. A secured network then asks for its password.
    public mutating func finish(error: String?) {
        guard case .joining(let ssid, let secured) = self else { return }
        self = switch (error, secured) {
        case (nil, _): .idle
        case (let error?, true): .password(ssid: ssid, error: error)
        case (let error?, false): .failed(ssid: ssid, error: error)
        }
    }
}
