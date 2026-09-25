import LiquidBarCore
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity
        )
    }

    static let barWhite = Color(hex: 0xf7f1ff)
    static let barGreen = Color(hex: 0x7bd88f)
    static let barYellow = Color(hex: 0xfce566)
    static let barRed = Color(hex: 0xfc618d)
}

let spring = Animation.spring(response: 0.35, dampingFraction: 0.72)

/// One bar per screen. `leftWidth`/`rightWidth` are the areas beside the notch; nil means no notch.
struct BarView: View {
    let model: BarModel
    let screenFrame: CGRect
    let leftWidth: CGFloat?
    let rightWidth: CGFloat?

    var body: some View {
        let config = model.config
        let island = config.height - 6
        HStack(spacing: 0) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(Array(config.left.enumerated()), id: \.offset) { _, widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, itemHeight: island - 6)
                    }
                }
                .padding(3)
                .frame(height: island)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(.leading, config.margin)
            .frame(width: leftWidth, alignment: .leading)

            Spacer(minLength: 0)

            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(Array(config.right.enumerated()), id: \.offset) { _, widget in
                        WidgetView(model: model, widget: widget, screenFrame: screenFrame, itemHeight: island)
                            .padding(.horizontal, 12)
                            .frame(height: island)
                            .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
            .padding(.trailing, config.margin)
            .frame(width: rightWidth, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(Color.barWhite)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WidgetView: View {
    let model: BarModel
    let widget: LiquidBarCore.Widget
    let screenFrame: CGRect
    let itemHeight: CGFloat

    var body: some View {
        switch widget {
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: itemHeight)
        case .workspaces:
            WorkspaceStrip(model: model, itemHeight: itemHeight)
        case .volume:
            Image(systemName: "speaker.wave.1.fill")
        case .wifi:
            Image(systemName: "wifi")
        case .battery:
            HStack(spacing: 5) {
                Image(systemName: "battery.50percent")
                Text("49%").font(.system(size: 12, weight: .bold))
            }
        case .clock:
            Text("19:34")
        case .date:
            Text("Fri. 25 Sep.")
        case .script(let script):
            HStack(spacing: 5) {
                if let symbol = script.symbol { Image(systemName: symbol) }
                Text(model.scriptLabels[script.script] ?? "")
            }
        }
    }
}

struct WorkspaceStrip: View {
    let model: BarModel
    let itemHeight: CGFloat
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.config.workspaces) { workspace in
                WorkspaceButton(
                    workspace: workspace,
                    focused: model.workspaces.focused == workspace.id,
                    occupied: model.workspaces.occupied.contains(workspace.id),
                    height: itemHeight,
                    ns: ns
                )
            }
        }
        .animation(spring, value: model.workspaces.focused)
    }
}

struct WorkspaceButton: View {
    let workspace: Workspace
    let focused: Bool
    let occupied: Bool
    let height: CGFloat
    let ns: Namespace.ID
    @State private var hovering = false
    @State private var bounce = 0

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: workspace.symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 18)
                .symbolEffect(.bounce, value: bounce)
            Text(workspace.id)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(focused ? Color.barWhite : occupied ? Color.barWhite.opacity(0.7) : Color(hex: 0x8b888f, opacity: 0.6))
        .padding(.horizontal, 8)
        .frame(height: height)
        .background {
            if focused {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                    .matchedGeometryEffect(id: "focus", in: ns)
            } else if hovering {
                Capsule().fill(.white.opacity(0.07))
            }
        }
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onChange(of: focused) { if focused { bounce += 1 } }
    }
}
