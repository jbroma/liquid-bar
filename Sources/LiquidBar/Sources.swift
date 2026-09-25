import AppKit
import CoreAudio
import AudioToolbox
import IOKit.ps
import LiquidBarCore
import Network

/// Runs a command (resolved through PATH) and returns stdout, or nil on failure.
nonisolated func run(_ args: [String]) async -> String? {
    await Task.detached {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }.value
}

func shell(_ command: String) {
    Task { _ = await run(["/bin/sh", "-c", command]) }
}

final class AeroSpaceSource {
    let model: BarModel
    private(set) var subscriber: Process?
    private var refreshTask: Task<Void, Never>?

    init(model: BarModel) {
        self.model = model
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshOccupancy() }
            }
        }
        Task { await subscribeForever() }
    }

    /// AeroSpace may start after us or restart; resubscribe with backoff.
    private func subscribeForever() async {
        var delay = 1.0
        while true {
            let started = Date()
            await subscribeOnce()
            if Date().timeIntervalSince(started) > 30 { delay = 1 }
            try? await Task.sleep(for: .seconds(delay))
            delay = min(delay * 2, 30)
        }
    }

    private func subscribeOnce() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["aerospace", "subscribe", "focus-changed", "focused-workspace-changed", "window-detected", "mode-changed"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return }
        subscriber = process
        refreshOccupancy()
        do {
            for try await line in out.fileHandleForReading.bytes.lines {
                guard let event = parseAeroEvent(line) else { continue }
                if model.workspaces.apply(event) { refreshOccupancy() }
            }
        } catch {}
        subscriber = nil
    }

    func refreshOccupancy() {
        refreshTask?.cancel()
        refreshTask = Task {
            // Window events arrive in bursts; coalesce them into one query.
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled,
                  let output = await run(["aerospace", "list-windows", "--all", "--format", "%{workspace}"]),
                  !Task.isCancelled
            else { return }
            let occupied = parseOccupied(output)
            if occupied != model.workspaces.occupied { model.workspaces.occupied = occupied }
        }
    }
}

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
    for source in list {
        guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              let current = d[kIOPSCurrentCapacityKey] as? Int,
              let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
        else { continue }
        // IOKit reports -1 minutes while it is still estimating.
        func minutes(_ key: String) -> Int? { (d[key] as? Int).flatMap { $0 >= 0 ? $0 : nil } }
        let power: BatteryState.Power =
            d[kIOPSPowerSourceStateKey] as? String != kIOPSACPowerValue ? .battery(minutesLeft: minutes(kIOPSTimeToEmptyKey))
            : d[kIOPSIsChargingKey] as? Bool == true ? .charging(minutesToFull: minutes(kIOPSTimeToFullChargeKey))
            : .pluggedIn
        return BatteryState(percent: current * 100 / max, power: power)
    }
    return nil
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

final class ClockSource {
    let model: BarModel
    private var timer: Timer?

    init(model: BarModel) {
        self.model = model
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
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
            FileHandle.standardError.write(Data("liquid-bar: ignoring \(configURL.path): \(error)\n".utf8))
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
        Task {
            guard let output = await run(["/bin/sh", "-c", script.script]) else { return }
            model.scriptLabels[script.script] = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
