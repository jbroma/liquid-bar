import AppKit
import LiquidBarCore

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
