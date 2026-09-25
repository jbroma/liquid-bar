import AppKit
import ApplicationServices

/// Tracks notification banners through the Accessibility API: while a banner shows, Notification Center's UI process
/// has a screen-sized window with the AXSystemDialog subrole, created with the banner and destroyed after it. Its
/// other windows are desktop widgets and stay put. Without Accessibility access it does nothing, and it attaches once
/// access is granted.
final class BannerWatcher {
    let model: BarModel
    private var observer: AXObserver?
    private var banners: [AXUIElement] = []
    private static let bundleID = "com.apple.notificationcenterui"

    init(model: BarModel) {
        self.model = model
        attach()
        // Posted system-wide whenever any app's Accessibility access changes.
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.accessibility.api"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachSoon() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Self.bundleID else { return }
            MainActor.assumeIsolated { self?.attach() }
        }
    }

    /// The trust flag updates a moment after the access-changed notification.
    private func attachSoon() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            attach()
        }
    }

    private func attach() {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).first?.processIdentifier
        else { return }
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        banners = []
        let callback: AXObserverCallback = { _, element, notification, context in
            MainActor.assumeIsolated {
                Unmanaged<BannerWatcher>.fromOpaque(context!).takeUnretainedValue().handle(element, notification as String)
            }
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(observer, app, kAXWindowCreatedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        (windows as? [AXUIElement] ?? []).forEach(track)
        publish()
    }

    private func handle(_ element: AXUIElement, _ notification: String) {
        if notification == kAXWindowCreatedNotification {
            track(element)
        } else {
            banners.removeAll { CFEqual($0, element) }
        }
        publish()
    }

    private func track(_ window: AXUIElement) {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        guard let observer, subrole as? String == kAXSystemDialogSubrole, !banners.contains(where: { CFEqual($0, window) }) else { return }
        banners.append(window)
        AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    /// The union of the banner windows' frames, in top-left-origin screen points.
    private func publish() {
        let frames = banners.compactMap(frame)
        let union = frames.dropFirst().reduce(frames.first) { $0?.union($1) }
        if union != model.banner { model.banner = union }
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(size as! AXValue, .cgSize, &extent),
              extent.width > 0, extent.height > 0
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
