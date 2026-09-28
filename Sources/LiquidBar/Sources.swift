import AppKit
import CoreAudio
import AudioToolbox
import IOKit.ps
import LiquidBarCore
import Network

/// Runs a shell command, like a click's action, without waiting for it or reading its output.
func shell(_ command: String) {
    let process = makeProcess(["/bin/sh", "-c", command])
    process.standardOutput = FileHandle.nullDevice
    try? process.run()
}

final class AeroSpaceSource {
    let model: BarModel
    private(set) var subscriber: Process?
    private var refreshTask: Task<Void, Never>?
    private var retry: Task<Void, Never>?

    init(model: BarModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let launched = name == NSWorkspace.didLaunchApplicationNotification
                    && (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == "bobko.aerospace"
                MainActor.assumeIsolated {
                    if launched { self?.retry?.cancel() }
                    self?.refreshWindows()
                }
            }
        }
        Task { await subscribeForever() }
    }

    /// AeroSpace may start after us or restart; resubscribe with backoff, or at once when it launches.
    private func subscribeForever() async {
        var backoff = Backoff()
        while true {
            let started = Date()
            await subscribeOnce()
            let wait = backoff.next(after: Date().timeIntervalSince(started))
            retry = Task { try? await Task.sleep(for: .seconds(wait)) }
            await retry?.value
        }
    }

    private func subscribeOnce() async {
        let process = makeProcess(["aerospace", "subscribe", "focus-changed", "focused-workspace-changed", "window-detected", "mode-changed"])
        let out = Pipe()
        process.standardOutput = out
        do { try process.run() } catch { return }
        subscriber = process
        // Seed focus so the focused workspace's stack is right before the first focus event.
        let seed = await run(["aerospace", "list-windows", "--focused", "--format", windowFormat])
        model.aerospaceConnected = seed != nil
        if let focused = seed.flatMap({ parseWindows($0).first }) {
            _ = model.workspaces.apply(.focusChanged(workspace: focused.workspace, windowID: focused.id))
        }
        refreshWindows()
        do {
            for try await line in out.fileHandleForReading.bytes.lines {
                guard let event = parseAeroEvent(line) else { continue }
                if model.workspaces.apply(event) { refreshWindows() }
            }
        } catch {}
        log.info("AeroSpace subscription ended")
        subscriber = nil
        model.aerospaceConnected = false
    }

    func refreshWindows() {
        refreshTask?.cancel()
        refreshTask = Task {
            // Window events arrive in bursts; coalesce them into one query.
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled,
                  let output = await run(["aerospace", "list-windows", "--all", "--format", windowFormat]),
                  !Task.isCancelled
            else { return }
            var state = model.workspaces
            state.setWindows(parseWindows(output))
            if state != model.workspaces { model.workspaces = state }
        }
    }
}

private let windowFormat = "%{workspace}|%{window-id}|%{app-bundle-id}"

final class BatterySource {
    let model: BarModel

    init(model: BarModel) {
        self.model = model
        model.battery = readBattery()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            MainActor.assumeIsolated {
                let source = Unmanaged<BatterySource>.fromOpaque(context!).takeUnretainedValue()
                let battery = readBattery()
                if battery != source.model.battery { source.model.battery = battery }
            }
        }
        if let loop = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loop, .defaultMode)
        }
    }
}

/// The internal battery, or nil on a desktop Mac.
nonisolated func readBattery() -> BatteryState? {
    guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    else { return nil }
    return list.lazy.compactMap { source in
        (IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]).flatMap(BatteryState.init(description:))
    }.first
}

/// Cycle count and wear from the `AppleSmartBattery` registry entry, readable without privileges.
nonisolated func readBatteryHealth() -> BatteryHealth? {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let registry = properties?.takeRetainedValue() as? [String: Any]
    else { return nil }
    return BatteryHealth(registry: registry)
}

/// The connected power adapter's rating, like 100.
nonisolated func adapterWatts() -> Int? {
    (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])?[kIOPSPowerAdapterWattsKey] as? Int
}

private nonisolated func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

private nonisolated let defaultOutput = address(kAudioHardwarePropertyDefaultOutputDevice)
private nonisolated let mainVolume = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
private nonisolated let mute = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)

private nonisolated func get<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var addr = addr
    var value = initial
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

private nonisolated func set<T: BitwiseCopyable>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) {
    var addr = addr
    var value = value
    AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value)
}

nonisolated func defaultOutputDevice() -> AudioObjectID {
    get(AudioObjectID(kAudioObjectSystemObject), defaultOutput, AudioObjectID(0)) ?? 0
}

nonisolated func setSystemVolume(_ level: Int) {
    let device = defaultOutputDevice()
    set(device, mainVolume, Float32(level) / 100)
    if level > 0 { set(device, mute, UInt32(0)) }
}

nonisolated func setMuted(_ muted: Bool) {
    set(defaultOutputDevice(), mute, UInt32(muted ? 1 : 0))
}

nonisolated func setDefaultOutputDevice(_ device: AudioObjectID) {
    set(AudioObjectID(kAudioObjectSystemObject), defaultOutput, device)
}

struct OutputDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbol: String
}

/// Every visible device that can play sound, in CoreAudio's order.
nonisolated func outputDevices() -> [OutputDevice] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var streams = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamsSize) == noErr, streamsSize > 0,
              (get(id, address(kAudioDevicePropertyIsHidden), UInt32(0)) ?? 0) == 0
        else { return nil }
        let name = deviceName(id)
        let transport = get(id, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0
        return OutputDevice(id: id, name: name, symbol: outputDeviceSymbol(transport: transport, name: name))
    }
}

nonisolated func deviceName(_ device: AudioObjectID) -> String {
    var addr = address(kAudioObjectPropertyName)
    var name: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name) == noErr, let name else { return "" }
    return name.takeRetainedValue() as String
}

final class VolumeSource {
    let model: BarModel
    private var device: AudioObjectID = 0

    // CoreAudio calls this on its own thread; the proc form (unlike blocks) can be removed again.
    private let changed: AudioObjectPropertyListenerProc = { _, _, _, context in
        let source = Unmanaged<VolumeSource>.fromOpaque(context!)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { source.takeUnretainedValue().followDefaultDevice() }
        }
        return noErr
    }

    init(model: BarModel) {
        self.model = model
        var addr = defaultOutput
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &addr, changed, Unmanaged.passUnretained(self).toOpaque())
        followDefaultDevice()
    }

    private func followDefaultDevice() {
        let current = defaultOutputDevice()
        if current != device {
            let context = Unmanaged.passUnretained(self).toOpaque()
            for var addr in [mainVolume, mute] {
                if device != 0 { AudioObjectRemovePropertyListener(device, &addr, changed, context) }
                AudioObjectAddPropertyListener(current, &addr, changed, context)
            }
            device = current
        }
        let level = get(device, mainVolume, Float32(0)) ?? 0
        let muted = (get(device, mute, UInt32(0)) ?? 0) != 0
        let state = VolumeState(level: Int((level * 100).rounded()), muted: muted, device: deviceName(device))
        if state != model.volume { model.volume = state }
    }
}

final class NetworkSource {
    private let monitor = NWPathMonitor()

    init(model: BarModel) {
        monitor.pathUpdateHandler = { path in
            let primary = path.availableInterfaces.first
            let state = NetworkState(
                kind: path.status != .satisfied ? .offline : primary?.type == .wifi ? .wifi : .wired,
                interface: path.status == .satisfied ? primary?.name : nil
            )
            MainActor.assumeIsolated { if state != model.network { model.network = state } }
        }
        monitor.start(queue: .main)
    }
}

/// Received and sent byte counters of one interface. They are 32-bit and wrap, so callers subtract with `&-`.
nonisolated func interfaceBytes(_ name: String) -> (received: UInt32, sent: UInt32)? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = entry.pointee
        guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), String(cString: ifa.ifa_name) == name,
              let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self).pointee
        else { continue }
        return (data.ifi_ibytes, data.ifi_obytes)
    }
    return nil
}

/// The interface's IPv4 address, like "192.168.1.23".
nonisolated func ipv4Address(_ name: String) -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let ifa = entry.pointee
        guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: ifa.ifa_name) == name else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
        return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    return nil
}

final class ClockSource {
    let model: BarModel
    private var timer: Timer?

    init(model: BarModel) {
        self.model = model
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Travel, a manual time zone or a clock set by hand.
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    NSTimeZone.resetSystemTimeZone()
                    self?.tick()
                }
            }
        }
        tick()
    }

    /// Updates the time and re-arms for the next minute boundary, so the label never lags.
    private func tick() {
        model.now = Date()
        let next = Date(timeIntervalSinceReferenceDate: (model.now.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60 + 60)
        timer?.invalidate()
        timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 0.2
        RunLoop.main.add(timer!, forMode: .common)
    }
}

let configURL = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".config/liquid-bar/config.json")

/// Reloads the config whenever the file or its directory changes. A missing file means defaults;
/// an invalid one is logged and ignored so the bar keeps its previous config.
final class ConfigWatcher {
    private let onChange: (Config) -> Void
    private var watches: [DispatchSourceFileSystemObject] = []

    init(onChange: @escaping (Config) -> Void) {
        self.onChange = onChange
        reload()
    }

    private func reload() {
        watches.forEach { $0.cancel() }
        let dir = configURL.deletingLastPathComponent()
        // Watch the directory for atomic saves, the file for in-place writes, and ~/.config until the directory exists.
        watches = [configURL, dir, dir.deletingLastPathComponent()].lazy.compactMap(watch).prefix(2).map { $0 }
        do {
            let data = try Data(contentsOf: configURL)
            onChange(try Config.decode(data))
        } catch CocoaError.fileReadNoSuchFile {
            onChange(Config())
        } catch {
            log.error("ignoring \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.reload() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
}

let triggerNotification = Notification.Name("dev.liquidbar.trigger")

/// SketchyBar-style script widgets: stdout becomes the label, refreshed on an interval and on `liquid-bar trigger <event>`.
final class ScriptRunner {
    let model: BarModel
    private var scripts: [ScriptWidget] = []
    private var timers: [Timer] = []
    /// Scripts with a run in flight. A slow script is not started again until its last run ends.
    private var running: Set<String> = []

    init(model: BarModel) {
        self.model = model
        DistributedNotificationCenter.default().addObserver(forName: triggerNotification, object: nil, queue: .main) { [weak self] note in
            let event = note.object as? String
            MainActor.assumeIsolated {
                guard let self, let event else { return }
                self.scripts.filter { $0.on?.contains(event) == true }.forEach(self.refresh)
            }
        }
    }

    func load(_ widgets: [Widget]) {
        let scripts = widgets.compactMap { widget -> ScriptWidget? in
            if case .script(let script) = widget { script } else { nil }
        }
        guard scripts != self.scripts else { return }
        self.scripts = scripts
        timers.forEach { $0.invalidate() }
        timers = scripts.compactMap { script in
            script.interval.map { interval in
                let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh(script) }
                }
                timer.tolerance = interval / 10
                RunLoop.main.add(timer, forMode: .common)
                return timer
            }
        }
        scripts.forEach(refresh)
    }

    private func refresh(_ script: ScriptWidget) {
        guard running.insert(script.script).inserted else { return }
        Task {
            let output = await run(["/bin/sh", "-c", script.script], timeout: 60)
            running.remove(script.script)
            guard let output else { return }
            model.scriptLabels[script.script] = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

/// Spotify and Music announce every play, pause and track change with a distributed notification, which needs no
/// permission. A paused player stays in the bar for five minutes.
final class NowPlayingSource {
    let model: BarModel
    private var hide: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private let artworkCache = NSCache<NSString, NSImage>()

    init(model: BarModel) {
        self.model = model
        artworkCache.countLimit = 20
        let notifications: [NowPlaying.Player: String] = [
            .spotify: "com.spotify.client.PlaybackStateChanged",
            .music: "com.apple.Music.playerInfo",
        ]
        for (player, name) in notifications {
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                let state = note.userInfo.flatMap { parseNowPlaying($0, player: player) }
                MainActor.assumeIsolated { self?.update(state, from: player) }
            }
        }
        queryRunningPlayers()
    }

    private func update(_ state: NowPlaying?, from player: NowPlaying.Player) {
        // One player stopping must not hide the other.
        guard state != nil || model.nowPlaying?.player == player else { return }
        if state?.trackID != model.nowPlaying?.trackID { loadArtwork(state) }
        model.nowPlaying = state
        hide?.cancel()
        guard let state, !state.playing else { return }
        hide = Task {
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            model.nowPlaying = nil
        }
    }

    /// Spotify artwork comes from its public oEmbed endpoint; Music shows its app icon.
    private func loadArtwork(_ state: NowPlaying?) {
        artworkTask?.cancel()
        guard let state else { return model.artwork = nil }
        if let cached = artworkCache.object(forKey: state.trackID as NSString) { return model.artwork = cached }
        model.artwork = AppIcons.icon(state.player.rawValue)
        guard state.player == .spotify, let id = spotifyTrackID(state.trackID) else { return }
        artworkTask = Task {
            struct OEmbed: Decodable { let thumbnail_url: URL }
            guard let (json, _) = try? await URLSession.shared.data(from: URL(string: "https://open.spotify.com/oembed?url=spotify:track:\(id)")!),
                  let oembed = try? JSONDecoder().decode(OEmbed.self, from: json),
                  let (data, _) = try? await URLSession.shared.data(from: oembed.thumbnail_url),
                  let image = NSImage(data: data), !Task.isCancelled
            else { return }
            artworkCache.setObject(image, forKey: state.trackID as NSString)
            model.artwork = image
        }
    }

    /// Players post nothing until their state changes, so ask a running one once at launch.
    private func queryRunningPlayers() {
        for player in [NowPlaying.Player.spotify, .music]
        where !NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).isEmpty {
            let idProperty = player == .spotify ? "id" : "persistent ID"
            let script = """
                tell application "\(player.appName)" to if player state is not stopped then ¬
                return (player state as string) & linefeed & name of current track & linefeed & artist of current track & linefeed & (\(idProperty) of current track as string)
                """
            Task {
                // The first run can wait on the Automation prompt.
                guard let output = await run(["osascript", "-e", script], timeout: 120) else { return }
                let fields = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 4 else { return }
                let info: [AnyHashable: Any] = [
                    "Player State": fields[0].capitalized, "Name": fields[1], "Artist": fields[2],
                    player == .spotify ? "Track ID" : "PersistentID": fields[3],
                ]
                update(parseNowPlaying(info, player: player), from: player)
            }
        }
    }
}

/// The frontmost app. The bar never activates, so this is always the app the user works in.
final class FrontAppSource {
    let model: BarModel

    init(model: BarModel) {
        self.model = model
        read(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.read(app) }
        }
    }

    private func read(_ app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return }
        let front = FrontApp(name: name, pid: app.processIdentifier)
        if front != model.frontApp { model.frontApp = front }
    }
}
