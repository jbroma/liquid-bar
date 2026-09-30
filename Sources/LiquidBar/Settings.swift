import AppKit
import LiquidBarCore
import SwiftUI

/// The LiquidBar Settings window: a standard macOS settings window, whatever the glass style.
@Observable
final class SettingsWindow {
    var section = SettingsSection.general
    @ObservationIgnored private var window: NSWindow?

    /// Shows the window, on `section` when given.
    func show(_ section: SettingsSection? = nil) {
        if let section { self.section = section }
        // The Accessibility window would float over this one; its row in General takes over.
        delegate.access.close()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 715, height: 500),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "LiquidBar Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: delegate.model, window: self))
            window.center()
            self.window = window
            followSystemAppearance()
            DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.followSystemAppearance() }
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The app is dark for the bar's sake; this window follows the system appearance like any settings window.
    private func followSystemAppearance() {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
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
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .menuBarItems: "menubar.rectangle"
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
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch section {
                case .general: GeneralPane(config: model.config)
                case .appearance: AppearancePane(config: model.config)
                case .menuBarItems: MenuBarItemsPane(model: model)
                }
            }
            // The sidebar already names the pane.
            .toolbar(removing: .title)
        }
        .frame(minWidth: 640, minHeight: 440)
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
            Section("Bar") {
                Picker("Workspaces", selection: saving(config.workspaceSource, Setting.workspaceSource)) {
                    Text("Automatic").tag(WorkspaceSource.auto)
                    Text("AeroSpace").tag(WorkspaceSource.aerospace)
                    Text("Desktops").tag(WorkspaceSource.spaces)
                    Text("Apps").tag(WorkspaceSource.apps)
                }
                Toggle("Show Now Playing", isOn: saving(config.right.contains(.nowPlaying), Setting.nowPlaying))
                Toggle("Show Battery Percentage", isOn: saving(config.batteryPercent, Setting.batteryPercent))
            }
            Section("Clock") {
                Picker("Format", selection: saving(config.clock24Hour, Setting.clock24Hour)) {
                    Text("System").tag(Bool?.none)
                    Text("24-Hour").tag(Bool?.some(true))
                    Text("12-Hour").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                Toggle("Show Seconds", isOn: saving(config.clockSeconds, Setting.clockSeconds))
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
                LabeledContent("Config File") {
                    Text(configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textSelection(.enabled)
                }
                LabeledContent("Started by", value: launcher)
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
            } footer: {
                Text("Every setting here is a key in the config file. Edits to the file show up here and on the bar right away.")
                    .foregroundStyle(.secondary)
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

private struct PermissionRow: View {
    let permission: Permission

    var body: some View {
        let status = permission.status
        LabeledContent {
            HStack(spacing: 10) {
                Image(systemName: status.symbol)
                    .foregroundStyle(status.color)
                    .help(title(status))
                    .accessibilityLabel(title(status))
                if status != .unknown {
                    let action = status == .notAsked ? "Grant…" : "Open Privacy & Security…"
                    Button { permission.request() } label: {
                        Image(systemName: status == .notAsked ? "arrow.forward.circle" : "gear")
                    }
                    .buttonStyle(.borderless)
                    .help(action)
                    .accessibilityLabel(action)
                }
            }
            .imageScale(.large)
        } label: {
            Label {
                Text(permission.title)
                Text(permission.use)
            } icon: {
                Image(systemName: permission.symbol).foregroundStyle(.secondary).frame(width: 22)
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

extension Permission.Status {
    fileprivate var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .notAsked: "exclamationmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
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
                Toggle("Show Pills", isOn: saving(config.pills, Setting.pills))
            } footer: {
                Text("Off, the bar's items sit straight on the bar, and a line marks the focused workspace.").foregroundStyle(.secondary)
            }
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 10)], spacing: 10) {
                    ForEach(GlassStyle.allCases, id: \.self) { style in
                        StyleCard(style: style, selected: !config.glassIsCustom && style == config.glassStyle)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Glass Style")
                    Spacer()
                    Picker("Preview", selection: $backdrop) {
                        ForEach(PreviewBackdropKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .fixedSize()
                }
            } footer: {
                Text("The glass of the dropdowns and the bar's pills.").foregroundStyle(.secondary)
            }
            CustomizeGroup(config: config)
        }
        .formStyle(.grouped)
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
        } header: {
            HStack {
                Text("Customize")
                if config.glassIsCustom { Text("Custom").foregroundStyle(.secondary) }
                Spacer()
                if config.glassIsCustom { Button("Reset to Preset") { Setting.glassStyle(config.glassStyle).save() } }
            }
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title).fontWeight(.semibold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GlassStyle.allCases, id: \.self) { style in
                        StyleSwatch(style: style, part: part, selected: style == selected)
                            .onTapGesture { pick(style) }
                    }
                }
                .padding(2)
            }
        }
    }
}

/// One style's pill or dropdown over the preset cards' backdrop.
private struct StyleSwatch: View {
    let style: GlassStyle
    let part: StylePart
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
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
            .environment(\.colorScheme, .dark)
            .frame(width: 64, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
            Text(style.title).font(.caption)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A style's glass over a colourful backdrop, so the styles differ as they do over busy windows.
private struct StyleCard: View {
    let style: GlassStyle
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
            .environment(\.colorScheme, .dark)
            .frame(height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(style.title).fontWeight(.semibold)
        }
        .help(style.summary)
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.primary.opacity(selected ? 0.12 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { Setting.glassStyle(style).save() }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Mirrors the pins of Control Center's Menu Bar Items: the pinned apps in bar order, which a drag reorders, then the
/// other status items.
private struct MenuBarItemsPane: View {
    let model: BarModel

    var body: some View {
        let pinned = model.config.pinned
        let others = trayItems(model.menuExtras).filter { !$0.bundleID.isEmpty && !pinned.contains($0.bundleID) }
        List {
            Section("On the Bar") {
                if pinned.isEmpty { Text("Nothing pinned yet").foregroundStyle(.secondary) }
                ForEach(pinned, id: \.self) { id in
                    let extra = model.menuExtras.first { $0.bundleID == id }
                    row(id, label: extra == nil ? "Not running" : extra?.label, pinned: true)
                }
                .onMove { from, to in
                    var order = pinned
                    order.move(fromOffsets: from, toOffset: to)
                    Setting.pinnedOrder(order).save()
                }
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
        .onAppear { MenuExtras.refresh(model) }
    }

    private func row(_ bundleID: String, label: String?, pinned: Bool) -> some View {
        HStack(spacing: 8) {
            if pinned { Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary) }
            Image(nsImage: AppIcons.icon(bundleID)).resizable().frame(width: 20, height: 20)
            Text(AppIcons.name(bundleID)).lineLimit(1)
            if let label { Text(label).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(minLength: 8)
            Button {
                Setting.pinned(bundleID, !pinned).save()
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .help(pinned ? "Unpin from the Bar" : "Pin to the Bar")
        }
        .padding(.vertical, 2)
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
