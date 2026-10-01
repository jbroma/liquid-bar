import SwiftUI

/// What is easy to miss on the bar. Each has a looping demo in the tips window and is ticked off there once the user
/// does it on the real bar.
enum Tip: Int, CaseIterable {
    case shift, pin, rightClick

    var title: String {
        switch self {
        case .shift: "The Front App's Menus"
        case .pin: "Other Apps' Menu Bar Items"
        case .rightClick: "Settings and Quit"
        }
    }

    var detail: String {
        switch self {
        case .shift: "Hold Shift with the pointer on the bar. The workspaces turn into the menus of the app in front."
        case .pin: "They are in Control Center, under Menu Bar Items. Pin the ones you want on the bar."
        case .rightClick: "Right-click anywhere on the bar for LiquidBar's own menu."
        }
    }

    var invitation: String {
        switch self {
        case .shift: "Try it now: hold Shift with the pointer on the bar"
        case .pin: "Try it now: open Control Center and unfold Menu Bar Items"
        case .rightClick: "Try it now: right-click the bar"
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
            Label(done ? "That's it" : tip.invitation, systemImage: done ? "checkmark.circle.fill" : "hand.point.up.left")
                .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .animation(.easeOut(duration: 0.2), value: done)
            HStack {
                Button("Back") { tip = Tip(rawValue: tip.rawValue - 1) ?? tip }
                    .opacity(tip == Tip.allCases.first ? 0 : 1)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(Tip.allCases, id: \.self) { page in
                        Circle().fill(page == tip ? Color.primary : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                    }
                }
                Spacer()
                Button(tip == Tip.allCases.last ? "Done" : "Next") {
                    if let next = Tip(rawValue: tip.rawValue + 1) { tip = next } else { close() }
                }
                .keyboardShortcut(.defaultAction)
            }
            .focusEffectDisabled()
            .padding(.top, 4)
        }
        .onAppear { UserDefaults.standard.set(true, forKey: AccessWindow.welcomed) }
    }
}

/// A demo is a small bar over a backdrop, drawn with the bar's own glass, that steps through a short loop.
private enum Demo {
    static let size = CGSize(width: 416, height: 150)
    static let font = Font.system(size: 11, weight: .semibold)
}

/// Counts through `steps` at a steady pace, animating each change.
private struct Loop<Content: View>: View {
    let steps: Int
    @ViewBuilder let content: (Int) -> Content
    @State private var step = 0

    var body: some View {
        content(step)
            .font(Demo.font)
            .foregroundStyle(.white)
            .frame(width: Demo.size.width, height: Demo.size.height, alignment: .topLeading)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1.1))
                    withAnimation(spring) { step = (step + 1) % steps }
                }
            }
    }
}

/// The arrow, with its tip at `at`.
private struct Pointer: View {
    let at: CGPoint

    var body: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
            .position(x: at.x + 5, y: at.y + 8)
    }
}

private extension View {
    /// A pill of the demo bar, in the user's bar style.
    func demoPill() -> some View {
        padding(.horizontal, 10).frame(height: 22).background { PillFill(shape: Capsule()) }
    }

    /// A dropdown of the demo bar, in the user's dropdown style.
    func demoDropdown(width: CGFloat) -> some View {
        padding(6).frame(width: width, alignment: .leading)
            .background(OverlayGlass(corner: 10, style: delegate.model.config.glass.dropdown))
    }
}

private struct Workspaces: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "apple.logo")
            ForEach(1...4, id: \.self) { number in
                Text("\(number)")
                    .frame(width: 18, height: 16)
                    .background { if number == 2 { PillFill(shape: Capsule()) } }
                    .opacity(number == 4 ? 0.5 : 1)
            }
        }
    }
}

private struct StatusItems: View {
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text("9:41")
        }
    }
}

/// The pointer goes to the bar, Shift goes down, and the workspaces turn into menus until it is let go.
private struct ShiftDemo: View {
    var body: some View {
        Loop(steps: 5) { step in
            let held = step == 2 || step == 3
            ZStack(alignment: .topLeading) {
                Group {
                    if held {
                        HStack(spacing: 11) {
                            Image(systemName: "apple.logo")
                            Text("Safari").fontWeight(.bold)
                            ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0) }
                        }
                        .transition(.opacity)
                    } else {
                        Workspaces().transition(.opacity)
                    }
                }
                .demoPill()
                .padding(8)
                Text("\(Image(systemName: "shift")) shift")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 84, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(held ? 0.5 : 0.16)))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(0.35)))
                    .scaleEffect(held ? 0.94 : 1)
                    .position(x: Demo.size.width / 2, y: 112)
                Pointer(at: step == 0 ? CGPoint(x: 290, y: 84) : CGPoint(x: 300, y: 18))
            }
        }
    }
}

/// Control Center opens, a pin is clicked under Menu Bar Items, and the item appears on the bar.
private struct PinDemo: View {
    var body: some View {
        Loop(steps: 6) { step in
            let pinned = step >= 3 && step < 5
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if pinned {
                        tile("timer", .orange).demoPill().transition(.scale.combined(with: .opacity))
                    }
                    StatusItems().demoPill()
                }
                .padding(8)
                if (1..<5).contains(step) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Menu Bar Items").padding(.leading, 2)
                        row("timer", .orange, "Timer", pinned: pinned)
                        row("shield.lefthalf.filled", .blue, "VPN", pinned: false)
                    }
                    .demoDropdown(width: 150)
                    .padding(.top, 36)
                    .padding(.trailing, 8)
                    .transition(.opacity)
                }
                Pointer(at: step == 0 || step == 5 ? CGPoint(x: 200, y: 96) : step == 1 ? CGPoint(x: 356, y: 20) : CGPoint(x: 271, y: 73))
            }
            .frame(width: Demo.size.width, height: Demo.size.height, alignment: .topTrailing)
        }
    }

    private func tile(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .frame(width: 15, height: 15)
            .background(tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func row(_ symbol: String, _ tint: Color, _ name: String, pinned: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: pinned ? "pin.fill" : "pin").font(.system(size: 9)).opacity(pinned ? 1 : 0.55).frame(width: 12)
            tile(symbol, tint)
            Text(name).fontWeight(.regular)
        }
        .frame(height: 20)
    }
}

/// The pointer goes to the bar, and a right-click opens LiquidBar's menu.
private struct RightClickDemo: View {
    var body: some View {
        Loop(steps: 5) { step in
            let open = step == 2 || step == 3
            ZStack(alignment: .topLeading) {
                HStack {
                    Workspaces().demoPill()
                    Spacer()
                    StatusItems().demoPill()
                }
                .padding(8)
                if open {
                    VStack(alignment: .leading, spacing: 2) {
                        entry("Check for Updates…", lit: false)
                        entry("LiquidBar Settings…", lit: step == 3)
                        Rectangle().fill(.white.opacity(0.2)).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 2)
                        entry("Quit LiquidBar", lit: false)
                    }
                    .fontWeight(.regular)
                    .demoDropdown(width: 150)
                    .offset(x: 196, y: 36)
                    .transition(.opacity)
                }
                Circle()
                    .strokeBorder(.white.opacity(step == 1 ? 0.9 : 0), lineWidth: 1.5)
                    .frame(width: 26, height: 26)
                    .scaleEffect(step == 1 ? 1 : 0.3)
                    .position(x: 208, y: 20)
                Pointer(at: step == 0 ? CGPoint(x: 280, y: 100) : step == 3 ? CGPoint(x: 290, y: 64) : CGPoint(x: 208, y: 20))
            }
        }
    }

    private func entry(_ title: String, lit: Bool) -> some View {
        Text(title)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(lit ? 0.18 : 0)))
    }
}
