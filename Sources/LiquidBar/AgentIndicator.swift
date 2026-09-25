import AppKit
import LiquidBarCore
import SwiftUI

/// Status at a glance: dots orbiting while working, an amber breath while waiting on the user, a check that draws
/// itself on finishing, red on failure. The looping ones run in Core Animation, so they cost the bar no CPU.
struct AgentIndicator: View {
    let status: AgentStatus
    let size: CGFloat

    var body: some View {
        Group {
            switch status {
            case .running: LoopingLayer(kind: .orbit, color: NSColor(status.color))
            case .needsInput: LoopingLayer(kind: .breath, color: NSColor(status.color))
            case .done: DrawnCheck(color: status.color)
            case .error:
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .foregroundStyle(.white, status.color)
            case .idle:
                Circle().fill(status.color).padding(size * 0.34)
            }
        }
        .frame(width: size, height: size)
        .transition(.blurReplace)
        .id(status)
    }
}

private struct DrawnCheck: View {
    let color: Color
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.2))
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .padding(4.5)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.45).delay(0.12)) { drawn = true } }
    }
}

private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.14))
        return path
    }
}

private struct LoopingLayer: NSViewRepresentable {
    enum Kind { case orbit, breath }
    let kind: Kind
    let color: NSColor

    func makeNSView(context: Context) -> LayerView { LayerView(kind: kind, color: color) }
    func updateNSView(_ view: LayerView, context: Context) {}

    final class LayerView: NSView {
        private let kind: Kind
        private let color: NSColor

        init(kind: Kind, color: NSColor) {
            self.kind = kind
            self.color = color
            super.init(frame: .zero)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            guard let layer, bounds.width > 0 else { return }
            layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            let side = min(bounds.width, bounds.height)
            switch kind {
            case .orbit:
                // Three dots on a ring, fading behind the leader, spinning once every 0.9s.
                let ring = CAReplicatorLayer()
                ring.frame = bounds
                ring.instanceCount = 3
                ring.instanceTransform = CATransform3DMakeRotation(-2 * .pi / 3, 0, 0, 1)
                ring.instanceAlphaOffset = -0.3
                let dot = CALayer()
                let d = side * 0.26
                dot.frame = CGRect(x: bounds.midX - d / 2, y: bounds.midY + side / 2 - d - side * 0.04, width: d, height: d)
                dot.cornerRadius = d / 2
                dot.backgroundColor = color.cgColor
                ring.addSublayer(dot)
                let track = CAShapeLayer()
                track.path = CGPath(ellipseIn: bounds.insetBy(dx: side * 0.17, dy: side * 0.17), transform: nil)
                track.fillColor = nil
                track.strokeColor = color.withAlphaComponent(0.22).cgColor
                track.lineWidth = side * 0.08
                layer.addSublayer(track)
                layer.addSublayer(ring)
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -2 * Double.pi
                spin.duration = 0.9
                spin.repeatCount = .infinity
                ring.add(spin, forKey: "spin")
            case .breath:
                let glow = CALayer()
                glow.frame = bounds.insetBy(dx: side * 0.08, dy: side * 0.08)
                glow.cornerRadius = glow.frame.width / 2
                glow.backgroundColor = color.withAlphaComponent(0.35).cgColor
                let core = CALayer()
                core.frame = bounds.insetBy(dx: side * 0.3, dy: side * 0.3)
                core.cornerRadius = core.frame.width / 2
                core.backgroundColor = color.cgColor
                layer.addSublayer(glow)
                layer.addSublayer(core)
                let breathe = CABasicAnimation(keyPath: "transform.scale")
                breathe.fromValue = 0.55
                breathe.toValue = 1
                breathe.duration = 1.1
                breathe.autoreverses = true
                breathe.repeatCount = .infinity
                breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0.25
                fade.toValue = 1
                fade.duration = 1.1
                fade.autoreverses = true
                fade.repeatCount = .infinity
                fade.timingFunction = breathe.timingFunction
                glow.add(breathe, forKey: "breathe")
                glow.add(fade, forKey: "fade")
            }
        }
    }
}
