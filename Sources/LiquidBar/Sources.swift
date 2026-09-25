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
                source.model.battery = readBattery()
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
        // Like `pmset -g batt | grep 'AC Power'`: plugged in counts as charging.
        let onAC = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        return BatteryState(percent: current * 100 / max, charging: onAC)
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
        let state = VolumeState(level: Int((level * 100).rounded()), muted: muted)
        if state != model.volume { model.volume = state }
    }
}

final class NetworkSource {
    private let monitor = NWPathMonitor()

    init(model: BarModel) {
        monitor.pathUpdateHandler = { path in
            let state: NetworkState =
                path.status != .satisfied ? .offline
                : path.availableInterfaces.contains { $0.type == .wifi } ? .wifi
                : .wired
            MainActor.assumeIsolated { model.network = state }
        }
        monitor.start(queue: .main)
    }
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
