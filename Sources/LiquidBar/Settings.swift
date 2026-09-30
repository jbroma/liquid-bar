import AppKit
import LiquidBarCore
import SwiftUI

/// The LiquidBar Settings window: a standard titled window on the config's glass.
@Observable
final class SettingsWindow {
    var section = SettingsSection.general
    @ObservationIgnored private var window: NSWindow?

    /// Shows the window, on `section` when given.
    func show(_ section: SettingsSection? = nil) {
        if let section { self.section = section }
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "LiquidBar Settings"
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: delegate.model, window: self))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, appearance, menuBarItems, advanced, about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .menuBarItems: "Menu Bar Items"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .menuBarItems: "menubar.rectangle"
        case .advanced: "wrench.and.screwdriver"
        case .about: "info.circle"
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
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch section {
                case .general: GeneralPane(config: model.config)
                case .appearance: AppearancePane(selected: model.config.glassStyle)
                case .menuBarItems: MenuBarItemsPane(model: model)
                case .advanced: AdvancedPane()
                case .about: ScrollView { AboutInfo().padding(.top, 60) }.frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(section.title)
        }
        .background(OverlayGlass(corner: 26).ignoresSafeArea())
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
                    Text("24-Hour").tag(true)
                    Text("12-Hour").tag(false)
                }
                .pickerStyle(.segmented)
                Toggle("Show Seconds", isOn: saving(config.clockSeconds, Setting.clockSeconds))
            }
            Section("Permissions") {
                // macOS posts nothing when the grant changes.
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    LabeledContent("Accessibility") {
                        HStack {
                            Text(AXIsProcessTrusted() ? "Allowed" : "Not allowed").foregroundStyle(.secondary)
                            Button("Open…") { delegate.access.show() }
                        }
                    }
                }
                LabeledContent("Started by", value: launcher)
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

private struct AppearancePane: View {
    let selected: GlassStyle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("The glass of the dropdowns, the bar's pills, and LiquidBar's windows.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(GlassStyle.allCases, id: \.self) { style in
                        StyleCard(style: style, selected: style == selected)
                    }
                }
            }
            .padding(20)
        }
    }
}

/// A style's glass over a colourful backdrop, so the styles differ as they do over busy windows.
private struct StyleCard: View {
    let style: GlassStyle
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                LinearGradient(colors: [.pink, .orange, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Text("Aa Bb Cc Dd\nEe Ff Gg Hh").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                    }
                VStack(alignment: .trailing, spacing: 6) {
                    Text("9:41")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .frame(height: 18)
                        .background(PillFill(shape: Capsule(), style: style))
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 24)
                        .background { Color.clear.glassEffect(.regular, in: .rect) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sound").fontWeight(.semibold)
                        Text("Speakers").foregroundStyle(secondary)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                    .background(OverlayGlass(corner: 12, style: style))
                    .padding([.horizontal, .bottom], 10)
                }
                .foregroundStyle(Color.barWhite)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(style.title).fontWeight(.semibold)
            Text(style.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(selected ? 0.12 : 0.04)))
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
                if !AXIsProcessTrusted() { Text("Reading other apps' items needs Accessibility access.").foregroundStyle(.secondary) }
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

private struct AdvancedPane: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Config file") {
                    Text(configURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).textSelection(.enabled)
                }
                HStack {
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
            } footer: {
                Text("Every setting here is a key in the config file. Edits to the file show up here and on the bar right away.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// The app's icon, version, link and license.
struct AboutInfo: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        return "Version \(short) (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
            Text("LiquidBar").font(.system(size: 20, weight: .semibold))
            Text(version).foregroundStyle(secondary)
            Text("A Liquid Glass menu bar for macOS")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Link("github.com/jbroma/liquid-bar", destination: URL(string: "https://github.com/jbroma/liquid-bar")!)
                .foregroundStyle(Color.accentColor)
                .pointerStyle(.link)
            Text("MIT License").foregroundStyle(secondary)
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
