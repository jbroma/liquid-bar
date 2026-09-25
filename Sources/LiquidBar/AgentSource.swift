import AppKit
import ApplicationServices
import LiquidBarCore

/// Keeps `model.agents` in step with T3 Code. T3 writes every change to `state.sqlite-wal`, so the source watches that
/// file (and the directory, for when the WAL is created, checkpointed away or replaced) and re-reads 250ms after the
/// last write. No polling: with T3 Code quiet or not installed, nothing runs.
final class AgentSource {
    let model: BarModel
    private let database: URL
    private var watches: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private var loggedError: String?

    init(model: BarModel, database: URL = T3Store.defaultURL) {
        self.model = model
        self.database = database
        rewatch()
    }

    private func rewatch() {
        watches.forEach { $0.cancel() }
        let wal = URL(fileURLWithPath: database.path + "-wal")
        watches = [wal, database.deletingLastPathComponent()].compactMap(watch)
        reload()
    }

    private func watch(_ url: URL) -> DispatchSourceFileSystemObject? {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let isWAL = url.path.hasSuffix("-wal")
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: isWAL ? [.write, .extend, .rename, .delete] : [.write], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            let events = source?.data ?? []
            MainActor.assumeIsolated {
                // The directory changes when the WAL comes or goes; either way the file watch must be re-armed.
                if !isWAL || !events.isDisjoint(with: [.rename, .delete]) { self?.rewatchSoon() } else { self?.reloadSoon() }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }

    private func reloadSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    private func rewatchSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            rewatch()
        }
    }

    func reload() {
        let database = database
        Task {
            let result = await Task.detached { Result { try T3Store.threads(at: database) } }.value
            switch result {
            case .success(let threads):
                loggedError = nil
                model.receive(threads)
            case .failure(let error):
                // A missing database just means T3 Code is not installed; a schema change is worth one line in the log.
                if "\(error)" != loggedError, FileManager.default.fileExists(atPath: database.path) {
                    FileHandle.standardError.write(Data("liquid-bar: T3 Code unavailable: \(error)\n".utf8))
                }
                loggedError = "\(error)"
                model.receive([])
            }
        }
    }
}

/// `liquid-bar agents [db]`: prints what the bar reads from T3 Code, one thread per line, for checking against sqlite3.
func printAgents(_ path: String?) -> Int32 {
    do {
        let threads = try T3Store.threads(at: path.map(URL.init(fileURLWithPath:)) ?? T3Store.defaultURL)
        for thread in threads {
            let fields = [thread.id, thread.project, thread.title, thread.provider.displayName, "\(thread.status)",
                          thread.turn.map { "\($0)" } ?? "-", thread.updatedAt.formatted(.iso8601)]
            print(fields.joined(separator: "\t"))
        }
        return 0
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        return 1
    }
}

/// Opening a thread in T3 Code. The desktop app registers `t3code://` only for its sign-in callback, so no URL can
/// select a thread: the bar activates the app, then presses the thread's row in T3's sidebar through Accessibility.
enum T3App {
    static let bundleID = "com.t3tools.t3code"

    /// Activating an app does not make AeroSpace switch workspaces, so the bar focuses T3's window through AeroSpace.
    static func open(_ thread: AgentThread, windows: [Window]) {
        if let window = windows.first(where: { $0.bundleID == bundleID }) {
            shell("aerospace focus --window-id \(window.id)")
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, _ in
            guard let pid = app?.processIdentifier else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                select(thread.title, pid: pid)
            }
        }
    }

    /// Presses the first pressable element titled `title` inside T3's windows. Electron builds its accessibility tree
    /// only once asked through `AXManualAccessibility`.
    @discardableResult
    static func select(_ title: String, pid: pid_t) -> Bool {
        guard AXIsProcessTrusted(), !title.isEmpty else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        var queue = children(app, kAXWindowsAttribute)
        var visited = 0
        while !queue.isEmpty, visited < 4000 {
            let element = queue.removeFirst()
            visited += 1
            let texts = [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute].compactMap { string(element, $0) }
            if texts.contains(title), let target = pressable(from: element) {
                return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
            }
            queue += children(element, kAXChildrenAttribute)
        }
        return false
    }

    /// The element or its nearest ancestor that is a link or button.
    private static func pressable(from element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        for _ in 0..<6 {
            guard let node = current else { return nil }
            let role = string(node, kAXRoleAttribute)
            if role == "AXLink" || role == kAXButtonRole { return node }
            var parent: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXParentAttribute as CFString, &parent)
            current = parent.map { $0 as! AXUIElement }
        }
        return nil
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value as? String : nil
    }

    private static func children(_ element: AXUIElement, _ name: String) -> [AXUIElement] {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value as? [AXUIElement] ?? [] : []
    }
}

extension BarModel {
    func open(_ thread: AgentThread) {
        T3App.open(thread, windows: workspaces.windows)
    }
}
