import LiquidBarCore
import SwiftUI

/// What is easy to miss on the bar. Each has a looping demo in the tips window and is ticked off there once the user
/// does it on the real bar. The last page has the Open at login switch in place of something to try.
enum Tip: Int, CaseIterable {
    case shift, pin, rightClick, login

    /// A launch agent already starts the bar at login, so its page is left out.
    static var pages: [Tip] { allCases.filter { $0 != .login || launchAgent == nil } }

    var title: String {
        switch self {
        case .shift: "The Front App's Menus"
        case .pin: "Other Apps' Menu Bar Items"
        case .rightClick: "Settings and Quit"
        case .login: "Start with Your Mac"
        }
    }

    var detail: String {
        switch self {
        case .shift: "Hold Shift with the pointer on the bar. The workspaces turn into the menus of the app in front."
        case .pin: "The bar covers them. Tick the ones you want on the bar in Settings, under Menu Bar Items."
        case .rightClick: "Right-click anywhere on the bar for LiquidBar's own menu."
        case .login: "LiquidBar can open when you log in. You can change this later in Settings, under General."
        }
    }

    var invitation: String {
        switch self {
        case .shift: "Try it now: hold Shift with the pointer on the bar"
        case .pin: "Try it now: right-click the bar, open Settings, and tick an item"
        case .rightClick: "Try it now: right-click the bar"
        case .login: ""
        }
    }
}

/// One tip per page: its demo, what to do, and whether the user has done it yet.
struct TipsView: View {
    let state: AccessWindow
    let close: () -> Void
    @State private var tip = Tip.shift

    var body: some View {
        let done = state.tried.contains(tip)
        VStack(spacing: 14) {
            Group {
                switch tip {
                case .shift: ShiftDemo()
                case .pin: PinDemo()
                case .rightClick: RightClickDemo()
                case .login: LoginDemo()
                }
            }
            .frame(width: Demo.size.width, height: Demo.size.height)
            .background(LinearGradient(colors: [Color(red: 0.42, green: 0.2, blue: 0.86), Color(red: 0.13, green: 0.36, blue: 0.9)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .environment(\.colorScheme, .dark)
            .id(tip)
            VStack(spacing: 6) {
                Text(tip.title).font(.title2.bold())
                Text(tip.detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 34, alignment: .top)
            }
            Group {
                if tip == .login {
                    LoginToggle().toggleStyle(.switch).controlSize(.small).fixedSize()
                } else {
                    Label(done ? "That's it" : tip.invitation, systemImage: done ? "checkmark.circle.fill" : "hand.point.up.left")
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeOut(duration: 0.2), value: done)
                }
            }
            // The switch is taller than the label, and no page may change the window's height.
            .frame(height: 22)
            HStack {
                Button("Back") { tip = Tip(rawValue: tip.rawValue - 1) ?? tip }
                    .opacity(tip == Tip.pages.first ? 0 : 1)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Tip.pages, id: \.self) { page in
                        Circle().fill(page == tip ? Color.primary : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button(tip == Tip.pages.last ? "Done" : "Next") {
                    if tip == Tip.pages.last { close() } else { tip = Tip(rawValue: tip.rawValue + 1) ?? tip }
                }
                .keyboardShortcut(.defaultAction)
            }
            .focusEffectDisabled()
            .padding(.top, 4)
        }
        .onAppear { UserDefaults.standard.set(true, forKey: AccessWindow.welcomed) }
    }
}

/// A demo is the bar at its real size over a backdrop, in the user's pill layout and glass, stepping through a short
/// loop. The pointer follows the target named for each step.
private enum Demo {
    static let size = CGSize(width: 416, height: 150)
    static let bar = BarMetrics()
    static var pills: PillLayout { delegate.model.config.pills }
}

/// Counts through `steps` at a steady pace, animating each change.
private struct Loop<Content: View>: View {
    let steps: Int
    var cursor = true
    /// Where the pointer's tip is at each step.
    let pointer: (Int) -> String
    @ViewBuilder let content: (Int, Namespace.ID) -> Content
    @State private var step = 0
    @Namespace private var targets

    var body: some View {
        content(step, targets)
            .font(.system(size: 12, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(width: Demo.size.width, height: Demo.size.height, alignment: .top)
            .background(alignment: .bottom) { Color.clear.frame(width: 1, height: 1).target("rest", targets).padding(.bottom, 44) }
            .overlay(alignment: .topLeading) {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(cursor ? 1 : 0)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                    // The arrow's tip, not its middle, goes on the target.
                    .offset(x: 5, y: 8)
                    .matchedGeometryEffect(id: pointer(step), in: targets, properties: .position, isSource: false)
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.1))
                    withAnimation(spring) { step = (step + 1) % steps }
                }
            }
    }
}

private extension View {
    /// Names this view's middle as a place the pointer can go.
    func target(_ name: String, _ targets: Namespace.ID) -> some View {
        background { Color.clear.frame(width: 1, height: 1).matchedGeometryEffect(id: name, in: targets, properties: .position) }
    }

    /// An item of the demo bar: in its own pill only when the pills are separate, like the real one.
    func demoItem(padding: CGFloat = 10) -> some View {
        let separate = Demo.pills == .separate
        return self.padding(.horizontal, separate ? padding : 7)
            .frame(height: Demo.bar.pill)
            .background { if separate { PillBackground(height: Demo.bar.pill, style: delegate.model.config.glass.bar, preview: true) } }
            .padding(.horizontal, itemGap / 2)
    }

    /// One side of the demo bar, in one capsule when the pills are grouped.
    func demoIsland() -> some View {
        background {
            if Demo.pills == .grouped { PillBackground(height: Demo.bar.pill, style: delegate.model.config.glass.bar, preview: true).frame(height: Demo.bar.pill).padding(.horizontal, itemGap / 2 - 4) }
        }
    }

    /// A dropdown of the demo bar, in the user's dropdown style.
    func demoDropdown(width: CGFloat) -> some View {
        font(.system(size: 12))
            .padding(6)
            .frame(width: width, alignment: .leading)
            .background(OverlayGlass(corner: 12, style: delegate.model.config.glass.dropdown))
    }
}

/// One end of the demo bar, as the card is a corner of the screen: the Apple logo and the workspaces, or the front
/// app's menus, at the left end, or the status items at the right end.
private struct DemoBar: View {
    var right = false
    var menus = false
    var pinned = false
    let targets: Namespace.ID
    /// Apps every Mac has, the first of each workspace in front.
    private let apps = [["com.apple.mail"], ["com.apple.Safari", "com.apple.Notes"], ["com.apple.Music"], []]

    var body: some View {
        HStack(spacing: 0) {
            if !right { leftEnd.fixedSize().demoIsland() }
            Color.clear.frame(width: 1, height: 1).target("bar", targets).frame(maxWidth: .infinity)
            if right { rightEnd.fixedSize().demoIsland() }
        }
        .padding(.horizontal, 10 - itemGap / 2)
        .frame(height: Demo.bar.height)
    }

    private var leftEnd: some View {
        HStack(spacing: 0) {
            Image(systemName: "apple.logo")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 3 + itemGap / 2)
            if menus {
                HStack(spacing: 0) {
                    Text("Safari").fontWeight(.bold).padding(.horizontal, 7)
                    ForEach(["File", "Edit", "View", "History"], id: \.self) { Text($0).fontWeight(.medium).padding(.horizontal, 7) }
                }
                .padding(.horizontal, itemGap / 2)
                .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
            } else {
                HStack(spacing: 0) { ForEach(apps.indices, id: \.self, content: workspace) }
                    .padding(.horizontal, itemGap / 2)
                    .transition(.blurReplace.combined(with: .scale(0.9, anchor: .leading)))
            }
        }
    }

    private var rightEnd: some View {
        HStack(spacing: 0) {
            if pinned {
                Image(nsImage: AppIcons.icon("com.apple.Passwords")).resizable().frame(width: 16, height: 16)
                    .demoItem()
                    .transition(.scale(0.6).combined(with: .opacity))
            }
            Image(systemName: "wifi").frame(width: 16).demoItem()
            Image(systemName: "battery.75percent").font(.system(size: 15)).demoItem()
            Image(systemName: "switch.2").frame(width: 16).demoItem()
            Text("9:41").demoItem(padding: 14)
        }
    }

    /// A workspace as the bar draws it: its apps' icons or a dot, and the number and the selection on the focused one.
    private func workspace(_ index: Int) -> some View {
        let focused = index == 1
        return HStack(spacing: 4) {
            if apps[index].isEmpty, !focused { Circle().fill(.white.opacity(0.35)).frame(width: 4, height: 4) }
            if !apps[index].isEmpty {
                IconStack(apps: apps[index].map { WorkspaceApp(bundleID: $0, windowID: 0, focused: false) }, more: 0)
            }
        }
        .padding(.horizontal, 7)
        .frame(minWidth: Demo.bar.item, minHeight: Demo.bar.item)
        .background(alignment: .bottom) {
            if focused {
                PillBackground(height: Demo.bar.item, style: delegate.model.config.glass.bar, preview: true)
            }
        }
    }
}

/// The pointer goes to the bar, Shift goes down, and the workspaces turn into menus until it is let go.
private struct ShiftDemo: View {
    var body: some View {
        Loop(steps: 5) { $0 == 0 ? "rest" : "bar" } content: { step, targets in
            let held = step == 2 || step == 3
            VStack(spacing: 0) {
                DemoBar(menus: held, targets: targets)
                Spacer()
                Text("\(Image(systemName: "shift")) shift")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 84, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(held ? 0.5 : 0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.35)))
                    .scaleEffect(held ? 0.94 : 1)
                    .offset(x: -70)
                    .padding(.bottom, 26)
            }
        }
    }
}

/// An item is ticked in the Settings window's Menu Bar Items pane, and it appears on the bar.
private struct PinDemo: View {
    var body: some View {
        Loop(steps: 6) { [0: "rest", 5: "rest"][$0] ?? "pin" } content: { step, targets in
            let pinned = step >= 2 && step < 5
            VStack(spacing: 12) {
                DemoBar(right: true, pinned: pinned, targets: targets)
                // The top of the Settings window; the card cuts off the rest.
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 8, height: 8) }
                        }
                        .padding(.leading, 4)
                        .padding(.bottom, 8)
                        ForEach(SettingsSection.allCases) { section in
                            Text(section.title)
                                .padding(.horizontal, 6)
                                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.accentColor.opacity(section == .menuBarItems ? 1 : 0)))
                        }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(8)
                    .frame(width: 112)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color(white: 0.17))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Other Menu Bar Items").font(.system(size: 11, weight: .bold)).padding(.bottom, 6)
                        VStack(spacing: 0) {
                            row("com.apple.Passwords", "Passwords", pinned: pinned, targets: targets)
                            Rectangle().fill(.white.opacity(0.1)).frame(height: 1).padding(.leading, 26)
                            row("com.apple.shortcuts", "Shortcuts", pinned: false, targets: nil)
                        }
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.06)))
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                }
                .frame(width: 330, height: 130)
                .background(Color(white: 0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            }
        }
    }

    /// A row of the Settings list; with `targets`, its checkbox is where the pointer goes.
    private func row(_ bundleID: String, _ name: String, pinned: Bool, targets: Namespace.ID?) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(pinned ? Color.accentColor : .white.opacity(0.18))
                .frame(width: 14, height: 14)
                .overlay { if pinned { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) } }
                .background { if let targets { Color.clear.frame(width: 1, height: 1).target("pin", targets) } }
            Image(nsImage: AppIcons.icon(bundleID)).resizable().frame(width: 18, height: 18)
            Text(name)
            Spacer()
        }
        .frame(height: 26)
    }
}

/// The pointer goes to the bar, and a right-click opens LiquidBar's menu.
private struct RightClickDemo: View {
    var body: some View {
        Loop(steps: 5) { [0: "rest", 3: "settings"][$0] ?? "bar" } content: { step, targets in
            let open = step == 2 || step == 3
            DemoBar(targets: targets)
                .overlay {
                    Circle()
                        .strokeBorder(.white.opacity(step == 1 ? 0.9 : 0), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                        .scaleEffect(step == 1 ? 1 : 0.3)
                        .matchedGeometryEffect(id: "bar", in: targets, properties: .position, isSource: false)
                }
                .overlay(alignment: .top) {
                    if open {
                        VStack(alignment: .leading, spacing: 0) {
                            entry("Check for Updates…", lit: false)
                            entry("LiquidBar Settings…", lit: step == 3).target("settings", targets)
                            Rectangle().fill(.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)
                            entry("Quit LiquidBar", lit: false)
                        }
                        .demoDropdown(width: 176)
                        .padding(.top, Demo.bar.height + 3)
                        .padding(.leading, 148)
                        .transition(.opacity)
                    }
                }
        }
    }

    private func entry(_ title: String, lit: Bool) -> some View {
        Text(title)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(lit ? 0.14 : 0)))
    }
}

/// The Mac logs in, and the bar drops into place on its own.
private struct LoginDemo: View {
    var body: some View {
        Loop(steps: 5, cursor: false) { _ in "rest" } content: { step, targets in
            let up = step > 0
            VStack(spacing: 0) {
                DemoBar(targets: targets)
                    .offset(y: up ? 0 : -Demo.bar.height)
                    .opacity(up ? 1 : 0)
                Spacer()
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .opacity(up ? 0 : 0.9)
                    .scaleEffect(up ? 0.7 : 1)
                Spacer()
            }
        }
    }
}
