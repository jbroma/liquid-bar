import AppKit
import LiquidBarCore
import Sparkle
import SwiftUI

/// The LiquidBar Settings window: a standard macOS settings window, whatever the glass style.
@Observable
final class SettingsWindow {
    var section = SettingsSection.general
    @ObservationIgnored private var window: AppWindow?

    init() {
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.followSystemAppearance() }
        }
    }

    /// Shows the window, on `section` when given.
    func show(_ section: SettingsSection? = nil) {
        if let section { self.section = section }
        // One permission request at a time; the Accessibility row in General takes over.
        delegate.access.close()
        if window == nil {
            let window = AppWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "LiquidBar Settings"
            window.isReleasedWhenClosed = false
            // SwiftUI puts the pane's title in the toolbar, as System Settings does, only once the window has one.
            window.toolbar = NSToolbar()
            window.toolbarStyle = .unified
            window.contentView = NSHostingView(rootView: SettingsView(model: delegate.model, window: self))
            if !window.setFrameUsingName("Settings") { window.center() }
            window.setFrameAutosaveName("Settings")
            // A closed window's SwiftUI content would keep updating, as the permission rows' timers do, so the window
            // goes with it and the next `show` builds a new one. The name frees for that one.
            window.onClose = { [weak self, weak window] in
                window?.setFrameAutosaveName("")
                self?.window = nil
            }
            self.window = window
            followSystemAppearance()
        }
        window.map(bringForward)
        // The sidebar takes the keyboard focus, as in System Settings, so its selection shows in the accent colour and
        // no control in the pane starts with a focus ring.
        DispatchQueue.main.async { [weak window] in
            window?.makeFirstResponder(window?.contentView.flatMap { firstTable(in: $0) })
        }
    }

    private func followSystemAppearance() { window?.appearance = systemAppearance() }
}

private func firstTable(in view: NSView) -> NSTableView? {
    view as? NSTableView ?? view.subviews.lazy.compactMap(firstTable).first
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, menuBarItems

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBarItems: "Menu Bar Items"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "circle.lefthalf.filled"
        case .menuBarItems: "switch.2"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: Color(white: 0.2)
        case .menuBarItems: .gray
        }
    }

    /// The System Settings pane with the same icon.
    var pane: String {
        switch self {
        case .general: "com.apple.systempreferences.GeneralSettings"
        case .appearance: "com.apple.Appearance-Settings.extension"
        case .menuBarItems: "com.apple.ControlCenter-Settings.extension"
        }
    }
}

/// Every control writes the config file through `Setting` and reads `model.config`, which the bar reloads from that
/// file, so edits made elsewhere show here too.
private struct SettingsView: View {
    let model: BarModel
    @Bindable var window: SettingsWindow

    var body: some View {
        let section = window.section
        return NavigationSplitView {
            List(SettingsSection.allCases, selection: $window.section) { section in
                Label { Text(section.title) } icon: { IconTile(symbol: section.symbol, tint: section.tint, system: .bundle(section.pane)) }.tag(section)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(232)
        } detail: {
            Group {
                switch section {
                case .general: GeneralPane(config: model.config)
                case .appearance: AppearancePane(config: model.config)
                case .menuBarItems: MenuBarItemsPane(model: model)
                }
            }
            .navigationTitle(section.title)
            // A grouped form starts some 20pt lower under the toolbar than System Settings' panes, and neither
            // `contentMargins` nor `safeAreaPadding` moves it.
            .padding(.top, -20)
        }
        // A fixed size, like System Settings' width and the Settings windows of Apple's apps: a resizable window
        // would be tiled by window managers such as AeroSpace.
        .frame(width: 740, height: 560)
    }
}

/// A binding that shows `value` and saves each change through `setting`.
private func saving<T>(_ value: T, _ setting: @escaping (T) -> Setting) -> Binding<T> {
    Binding(get: { value }, set: { setting($0).save() })
}

private struct GeneralPane: View {
    let config: Config

    var body: some View {
        Form {
            Section {
                Picker("Workspaces", selection: saving(config.workspaceSource, Setting.workspaceSource)) {
                    Text("Automatic").tag(WorkspaceSource.auto)
                    Text("AeroSpace").tag(WorkspaceSource.aerospace)
                    Text("Desktops").tag(WorkspaceSource.spaces)
                    Text("Apps").tag(WorkspaceSource.apps)
                }
                Toggle("Show now playing", isOn: saving(config.right.contains(.nowPlaying), Setting.nowPlaying))
                Toggle("Show battery percentage", isOn: saving(config.batteryPercent, Setting.batteryPercent))
            }
            Section("Clock") {
                Picker("Format", selection: saving(config.clock24Hour, Setting.clock24Hour)) {
                    Text("System").tag(Bool?.none)
                    Text("24-Hour").tag(Bool?.some(true))
                    Text("12-Hour").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                Toggle("Show seconds", isOn: saving(config.clockSeconds, Setting.clockSeconds))
            }
            Section {
                ForEach(Permission.listed) { permission in
                    // macOS posts nothing when a grant changes.
                    TimelineView(.periodic(from: .now, by: 2)) { _ in PermissionRow(permission: permission) }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("LiquidBar asks for each one the first time you use what needs it.").foregroundStyle(.secondary)
            }
            Section {
                LabeledContent {
                    Text(configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textSelection(.enabled)
                } label: {
                    Label { Text("Config file") } icon: { IconTile(symbol: "doc.text.fill", tint: .gray) }
                }
                LabeledContent {
                    Text(launcher).foregroundStyle(.secondary)
                } label: {
                    Label { Text("Started by") } icon: { IconTile(symbol: "power", tint: .green) }
                }
                HStack {
                    Spacer()
                    Button("Open Config File…") {
                        do {
                            try createConfigFile(at: configURL)
                            NSWorkspace.shared.open(configURL)
                        } catch {
                            log.error("cannot create \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
                        }
                    }
                    Button("Reload Config") { delegate.configWatcher?.reload() }
                }
            } header: {
                Text("Configuration")
            }
            Section("Updates") {
                if let updater = delegate.updates.updater {
                    UpdateRows(updater: updater)
                } else {
                    Text("Updated by your Nix configuration").foregroundStyle(.secondary)
                }
            }
            Section {
                AboutLine()
            }
        }
        .formStyle(.grouped)
    }

    /// launchd names a launch agent's job after its label, and an app opened from Finder or `open` "application.…".
    private var launcher: String {
        let job = ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? ""
        return job.isEmpty || job == "0" || job.hasPrefix("application.") ? "Opened by hand" : "Launch agent \(job)"
    }
}

/// System Settings' own icon when `system` names one, drawn by macOS; otherwise a white SF Symbol on a rounded
/// square with System Settings' top-to-bottom gradient.
struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20
    var system: SystemIcon?

    var body: some View {
        if let image = system?.image(size: size * 1.18) {
            // IconServices leaves a margin around the tile, which System Settings' lists draw outside the row's icon size.
            Image(nsImage: image).resizable().frame(width: size * 1.18, height: size * 1.18).padding(-size * 0.09)
        } else {
            tile
        }
    }

    private var tile: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [tint.mix(with: .white, by: 0.18), tint], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}

private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        let status = permission.status
        LabeledContent {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Circle().fill(status.color).frame(width: 7, height: 7)
                    Text(status.label).foregroundStyle(.secondary)
                }
                .help(title(status))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title(status))
                if status == .notAsked {
                    Button("Grant…") { permission.request() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Grant…")
                } else if status != .unknown {
                    Button { permission.request() } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Open Privacy & Security…")
                    .accessibilityLabel("Open Privacy & Security…")
                }
            }
        } label: {
            Label {
                Text(permission.title)
                Text(permission.use)
            } icon: {
                IconTile(symbol: permission.symbol, tint: permission.tint, system: .type(permission.graphicIcon))
            }
        }
    }

    private func title(_ status: Permission.Status) -> String {
        switch status {
        case .granted: "Allowed"
        case .notAsked: "Not asked yet"
        case .denied: "Not allowed"
        case .unknown: "Known while \(permission.app?.name ?? "it") runs"
        }
    }
}

/// An icon System Settings shows, which IconServices draws from a symbol and colour that the pane's Info.plist names:
/// a pane by its bundle id, or a Privacy & Security row by its `com.apple.graphic-icon` type.
enum SystemIcon: Hashable {
    case bundle(String), type(String)

    private static var cache: [Key: NSImage?] = [:]
    private struct Key: Hashable { let icon: SystemIcon, size: CGFloat }

    /// Nil if IconServices, a private framework, changes and no longer answers.
    func image(size: CGFloat) -> NSImage? {
        let key = Key(icon: self, size: size)
        if let cached = Self.cache[key] { return cached }
        let image = render(size: size)
        Self.cache[key] = image
        return image
    }

    private func render(size: CGFloat) -> NSImage? {
        typealias Make = @convention(c) (AnyObject, Selector, NSString) -> AnyObject?
        typealias Describe = @convention(c) (AnyObject, Selector, CGSize, CGFloat) -> AnyObject?
        typealias Draw = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
        typealias Bitmap = @convention(c) (AnyObject, Selector) -> Unmanaged<CGImage>?
        func alloc(_ name: String) -> AnyObject? {
            (NSClassFromString(name) as AnyObject?)?.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        }
        func method<F>(_ object: AnyObject, _ name: String, as: F.Type) -> (F, Selector)? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector), let imp = object.method(for: selector) else { return nil }
            return (unsafeBitCast(imp, to: F.self), selector)
        }
        let (initializer, id) = switch self {
        case .bundle(let id): ("initWithBundleIdentifier:", id)
        case .type(let id): ("initWithType:", id)
        }
        guard dlopen("/System/Library/PrivateFrameworks/IconServices.framework/IconServices", RTLD_LAZY) != nil,
              let newIcon = alloc("ISIcon"), let (make, makeSel) = method(newIcon, initializer, as: Make.self),
              let icon = make(newIcon, makeSel, id as NSString),
              let newDescriptor = alloc("ISImageDescriptor"),
              let (describe, describeSel) = method(newDescriptor, "initWithSize:scale:", as: Describe.self),
              let descriptor = describe(newDescriptor, describeSel, CGSize(width: size, height: size), NSScreen.main?.backingScaleFactor ?? 2),
              // Waits for the drawing, where `imageForDescriptor:` would return a placeholder at first.
              let (prepare, prepareSel) = method(icon, "prepareImageForDescriptor:", as: Draw.self),
              let drawn = prepare(icon, prepareSel, descriptor),
              let (bitmap, bitmapSel) = method(drawn, "CGImage", as: Bitmap.self),
              let cgImage = bitmap(drawn, bitmapSel)?.takeUnretainedValue()
        else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}

extension Permission {
    /// Its row's icon in System Settings' Privacy & Security.
    fileprivate var graphicIcon: String {
        switch self {
        case .accessibility: "com.apple.graphic-icon.accessibility"
        case .bluetooth: "com.apple.graphic-icon.bluetooth"
        case .location: "com.apple.graphic-icon.location"
        case .spotify, .music, .loginwindow: "com.apple.graphic-icon.automation"
        }
    }

    /// System Settings' Privacy & Security colours: blue for the system services, gray for Automation.
    fileprivate var tint: Color {
        switch self {
        case .accessibility, .bluetooth, .location: .blue
        case .spotify, .music, .loginwindow: .gray
        }
    }
}

extension Permission.Status {
    fileprivate var label: String {
        switch self {
        case .granted: "Allowed"
        case .notAsked: "Not asked"
        case .denied: "Not allowed"
        case .unknown: "Not running"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .granted: .green
        case .notAsked: .orange
        case .denied: .red
        case .unknown: .secondary
        }
    }
}

private struct AppearancePane: View {
    let config: Config
    @AppStorage("previewBackdrop") private var backdrop = PreviewBackdropKind.wallpaper

    var body: some View {
        Form {
            Section {
                Toggle(isOn: saving(config.pills, Setting.pills)) {
                    Text("Show pills")
                    Text("Off, the items sit straight on the bar.")
                }
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(GlassStyle.allCases, id: \.self) { style in
                        StyleCard(style: style, selected: !config.glassIsCustom && style == config.glassStyle)
                    }
                }
                .padding(.vertical, 4)
                Picker("Preview background", selection: $backdrop) {
                    ForEach(PreviewBackdropKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Glass Style")
            }
            CustomizeGroup(config: config)
        }
        .formStyle(.grouped)
    }
}

/// System Settings' thumbnail choice: an accent ring around the selected thumbnail, and its caption in bold.
private struct Choice<Thumbnail: View>: View {
    let title: String
    let selected: Bool
    var corner: CGFloat = 8
    let pick: () -> Void
    @ViewBuilder let thumbnail: Thumbnail

    var body: some View {
        VStack(spacing: 5) {
            thumbnail
                .environment(\.colorScheme, .dark)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: corner + 3, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5)
                }
            Text(title)
                .font(.callout)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: pick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// What the Appearance previews sit on. A UI preference in UserDefaults: it does not change the bar.
private enum PreviewBackdropKind: String, CaseIterable {
    case wallpaper, light, dark, busy

    var title: String { rawValue.capitalized }
}

/// The main screen's desktop picture, read again only when its file changes.
@MainActor private enum Wallpaper {
    private static var cached: (url: URL, image: NSImage?)?

    static var image: NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        if cached?.url != url { cached = (url, NSImage(contentsOf: url)) }
        return cached?.image
    }
}

private struct PreviewBackdrop: View {
    /// The busy backdrop's sample text, which shows how legible a style's glass leaves what is behind it.
    let text: Bool
    @AppStorage("previewBackdrop") private var kind = PreviewBackdropKind.wallpaper

    var body: some View {
        switch kind {
        case .wallpaper:
            if let image = Wallpaper.image {
                Color.clear.overlay { Image(nsImage: image).resizable().scaledToFill() }.clipped()
            } else {
                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.3)], startPoint: .top, endPoint: .bottom)
            }
        case .light: LinearGradient(colors: [Color(white: 0.97), Color(white: 0.82)], startPoint: .top, endPoint: .bottom)
        case .dark: LinearGradient(colors: [Color(white: 0.04), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
        case .busy:
            LinearGradient(colors: [.pink, .orange, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay {
                    if text { Text("Aa Bb Cc Dd\nEe Ff Gg Hh").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white.opacity(0.5)) }
                }
        }
    }
}

/// Bar and dropdown styles picked apart, from the same seven styles as the presets.
private struct CustomizeGroup: View {
    let config: Config

    var body: some View {
        Section {
            StylePicker(title: "Bar", selected: config.glass.bar, part: .bar) { Setting.barStyle($0).save() }
            StylePicker(title: "Dropdowns", selected: config.glass.dropdown, part: .dropdown) { Setting.dropdownStyle($0).save() }
            if config.glassIsCustom {
                LabeledContent("Custom mix") {
                    Button("Reset to \(config.glassStyle.title)") { Setting.glassStyle(config.glassStyle).save() }
                }
            }
        } header: {
            Text("Customize")
        }
    }
}

private enum StylePart { case bar, dropdown }

private struct StylePicker: View {
    let title: String
    let selected: GlassStyle
    let part: StylePart
    let pick: (GlassStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
            HStack(spacing: 6) {
                ForEach(GlassStyle.allCases, id: \.self) { style in
                    Choice(title: style.title, selected: style == selected, corner: 7, pick: { pick(style) }) {
                        StyleSwatch(style: style, part: part)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// One style's pill or dropdown over the preset cards' backdrop.
private struct StyleSwatch: View {
    let style: GlassStyle
    let part: StylePart

    var body: some View {
        ZStack {
            PreviewBackdrop(text: false)
            switch part {
            case .bar:
                Text("9:41")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 18)
                    .background(PillFill(shape: Capsule(), style: style))
            case .dropdown:
                Text("Sound")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 44, height: 24)
                    .background(OverlayGlass(corner: 8, style: style))
            }
        }
        .foregroundStyle(Color.barWhite)
        .frame(width: 54, height: 34)
    }
}

/// A style's glass over a colourful backdrop, so the styles differ as they do over busy windows.
private struct StyleCard: View {
    let style: GlassStyle
    let selected: Bool

    var body: some View {
        Choice(title: style.title, selected: selected, pick: { Setting.glassStyle(style).save() }) {
            ZStack(alignment: .top) {
                PreviewBackdrop(text: true)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("9:41")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(PillFill(shape: Capsule(), style: style))
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 22)
                        .background { Color.clear.glassEffect(.regular, in: .rect) }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sound").fontWeight(.semibold)
                        Text("Speakers").foregroundStyle(secondary)
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(6)
                    .background(OverlayGlass(corner: 10, style: style))
                    .padding([.horizontal, .bottom], 6)
                }
                .foregroundStyle(Color.barWhite)
            }
            .frame(height: 64)
        }
        .help(style.summary)
    }
}

/// Mirrors the pins of Control Center's Menu Bar Items: the pinned apps in bar order, which a drag reorders, then the
/// other status items.
private struct MenuBarItemsPane: View {
    let model: BarModel

    var body: some View {
        let pinned = model.config.pinned
        let others = trayItems(model.menuExtras).filter { !$0.bundleID.isEmpty && !pinned.contains($0.bundleID) }
        Form {
            Section {
                if pinned.isEmpty { Text("Nothing pinned yet").foregroundStyle(.secondary) }
                // A grouped form has no `onMove`, so each row is dragged onto the row whose place it takes.
                ForEach(pinned, id: \.self) { id in
                    let extra = model.menuExtras.first { $0.bundleID == id }
                    row(id, label: extra == nil ? "Not running" : extra?.label, pinned: true)
                        .draggable(id) { Image(nsImage: AppIcons.icon(id)).resizable().frame(width: 32, height: 32) }
                        .dropDestination(for: String.self) { dropped, _ in
                            guard let moved = dropped.first, let from = pinned.firstIndex(of: moved),
                                  let to = pinned.firstIndex(of: id), from != to else { return false }
                            var order = pinned
                            order.move(fromOffsets: [from], toOffset: to > from ? to + 1 : to)
                            Setting.pinnedOrder(order).save()
                            return true
                        }
                }
            } header: {
                Text("On the Bar")
            }
            Section("Other Menu Bar Items") {
                if !AXIsProcessTrusted() {
                    LabeledContent("Reading other apps' items needs Accessibility access.") {
                        Button("Grant…") { Permission.accessibility.request() }
                    }
                    .foregroundStyle(.secondary)
                }
                ForEach(Array(others.enumerated()), id: \.offset) { _, extra in
                    row(extra.bundleID, label: extra.label, pinned: false)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { MenuExtras.refresh(model) }
    }

    /// System Settings' Menu Bar list: a checkbox, the app's icon and name.
    private func row(_ bundleID: String, label: String?, pinned: Bool) -> some View {
        HStack(spacing: 8) {
            Toggle(AppIcons.name(bundleID), isOn: Binding(get: { pinned }, set: { Setting.pinned(bundleID, $0).save() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(pinned ? "Unpin from the Bar" : "Pin to the Bar")
            Image(nsImage: AppIcons.icon(bundleID)).resizable().frame(width: 22, height: 22)
            Text(AppIcons.name(bundleID)).lineLimit(1)
            if let label { Text(label).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 8)
            if pinned { Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true) }
        }
    }
}

/// Sparkle keeps the automatic-check preference in its own defaults, so the toggle writes straight to the updater.
private struct UpdateRows: View {
    let updater: SPUUpdater
    @State private var automatic: Bool
    @State private var canCheck = false

    init(updater: SPUUpdater) {
        self.updater = updater
        _automatic = State(initialValue: updater.automaticallyChecksForUpdates)
    }

    var body: some View {
        Toggle("Check for updates automatically", isOn: $automatic)
            .onChange(of: automatic) { updater.automaticallyChecksForUpdates = $1 }
        HStack {
            Spacer()
            Button("Check Now") { delegate.updates.check() }
                .disabled(!canCheck)
        }
        .onReceive(updater.publisher(for: \.canCheckForUpdates)) { canCheck = $0 }
    }
}

/// The app's icon, version, link and license on one line, at the foot of General.
private struct AboutLine: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
            Text("LiquidBar \(version)")
            Spacer()
            Link("github.com/jbroma/liquid-bar", destination: URL(string: "https://github.com/jbroma/liquid-bar")!)
                .pointerStyle(.link)
            Text("MIT License").foregroundStyle(.secondary)
        }
    }
}

extension Setting {
    /// Edits the config file, which the bar reloads like any other edit.
    func save() {
        do {
            let data = try applied(to: try? Data(contentsOf: configURL))
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
        } catch {
            log.error("cannot change \(configURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}

/// A standard window of LiquidBar's: Esc closes it, like ⌘W.
final class AppWindow: NSWindow {
    var onClose: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { performClose(sender) }

    override func close() {
        super.close()
        onClose?()
    }
}

/// LiquidBar has no Dock icon, so its windows would open behind the front app, with dimmed buttons, and Command-Tab
/// would skip them. While one is up it is a regular app, and the window opens on the Space the user is on.
func bringForward(_ window: NSWindow) {
    window.collectionBehavior.insert(.moveToActiveSpace)
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    // Plain `activate()` is only a request, which macOS turns down for an app launched in the background, as by
    // launchd at login: the window then opened behind the front app with dimmed buttons.
    NSApp.activate(ignoringOtherApps: true)
}

/// Makes LiquidBar an accessory app again once none of its titled windows, its own or Sparkle's, is on screen.
func followWindows() {
    DispatchQueue.main.async {
        guard !NSApp.windows.contains(where: { $0.isVisible && $0.styleMask.contains(.titled) }) else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The app is dark for the bar's sake; its standard windows follow the system appearance instead.
/// Read from SkyLight: the process's cached `AppleInterfaceStyle` default still said Dark after a switch to Light.
func systemAppearance() -> NSAppearance? {
    NSAppearance(named: Appearance.isDark() ?? true ? .darkAqua : .aqua)
}
