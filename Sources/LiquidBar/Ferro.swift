import AppKit
import LiquidBarCore
import Metal
import QuartzCore

/// The ferrofluid shader, compiled from source at launch: the offline Metal compiler is an optional Xcode download,
/// the runtime compiler ships with macOS.
let ferroShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Header {
    float2 size;      // view size in points
    float scale;      // pixels per point
    float inset;      // glass wall thickness
    float4 tint;      // rim colour away from tinted beads
    int beads;
    int spikes;
    int pad0;
    int pad1;
};

struct VOut { float4 position [[position]]; };

vertex VOut ferroVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    VOut out;
    out.position = float4(p * 2 - 1, 0, 1);
    return out;
}

static float smin(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// A capsule: center, half width, half height.
static float capsule(float2 p, float4 b) {
    float r = b.w;
    float2 q = p - b.xy;
    q.x = max(abs(q.x) - max(b.z - r, 0.0), 0.0);
    return length(q) - r;
}

// A spike tapering from a round base to a fine tip.
static float spike(float2 p, float4 s) {
    float2 a = s.xy, b = s.zw;
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h) - mix(2.4, 0.35, h);
}

static float field(float2 p, constant Header &u, constant float4 *beads, constant float4 *spikes) {
    float d = 1e5;
    for (int i = 0; i < u.beads; i++) d = smin(d, capsule(p, beads[i]), 9.0);
    for (int i = 0; i < u.spikes; i++) d = smin(d, spike(p, spikes[i]), 2.5);
    // The glass holds it: nothing crosses the vessel's inner wall.
    float r = u.size.y / 2 - u.inset;
    float2 c = float2(clamp(p.x, u.size.y / 2, u.size.x - u.size.y / 2), u.size.y / 2);
    return max(d, length(p - c) - r);
}

// The rim colour at p: each bead's own colour near it, the header's colour elsewhere.
static float3 tintAt(float2 p, constant Header &u, constant float4 *beads, constant float4 *tints) {
    float3 sum = u.tint.rgb * u.tint.a * 0.25;
    float weight = 0.25;
    for (int i = 0; i < u.beads; i++) {
        float w = exp(-max(capsule(p, beads[i]), 0.0) / 6);
        sum += tints[i].rgb * tints[i].a * w;
        weight += tints[i].a * w;
    }
    return sum / weight;
}

fragment float4 ferroFragment(VOut in [[stage_in]], constant Header &u [[buffer(0)]], constant float4 *beads [[buffer(1)]],
                              constant float4 *spikes [[buffer(2)]], constant float4 *tints [[buffer(3)]]) {
    float2 p = in.position.xy / u.scale;
    float d = field(p, u, beads, spikes);
    float alpha = clamp(0.5 - d * u.scale, 0.0, 1.0);
    if (alpha <= 0) return float4(0);
    // A domed body: the normal leans outward over a wide rounded edge and faces the viewer in the middle.
    float h = 0.35;
    float2 g = float2(field(p + float2(h, 0), u, beads, spikes) - field(p - float2(h, 0), u, beads, spikes),
                      field(p + float2(0, h), u, beads, spikes) - field(p - float2(0, h), u, beads, spikes));
    float2 outward = length(g) > 0.0001 ? normalize(g) : float2(0, -1);
    float t = 1 - clamp(-d / 7.0, 0.0, 1.0);
    t = t * t * (3 - 2 * t);
    float3 n = normalize(float3(outward * t, sqrt(max(0.0, 1 - t * t))));
    float3 v = float3(0, 0, 1);
    float3 key = normalize(float3(-0.45, -0.7, 0.55));   // y grows down, so light from above has negative y
    float3 fill = normalize(float3(0.6, 0.35, 0.72));
    float spec = pow(max(dot(n, normalize(key + v)), 0.0), 110.0) * 1.6 + pow(max(dot(n, normalize(fill + v)), 0.0), 36.0) * 0.14;
    float fresnel = pow(1 - n.z, 2.0);
    // The environment: a pale sky above, a dark floor below.
    float3 env = mix(float3(0.03, 0.03, 0.035), float3(0.55, 0.6, 0.68), clamp(0.5 - n.y * 0.9, 0.0, 1.0));
    float3 color = float3(0.008) + env * fresnel * 0.42 + tintAt(p, u, beads, tints) * fresnel * 0.9 + spec;
    return float4(min(color, 1.0) * alpha, alpha);
}
"""

private struct Header {
    var size: SIMD2<Float>
    var scale: Float
    var inset: Float
    var tint: SIMD4<Float>
    var beads: Int32
    var spikes: Int32
    var pad0: Int32 = 0
    var pad1: Int32 = 0
}

@MainActor
enum FerroPipeline {
    static let device = MTLCreateSystemDefaultDevice()
    static let queue = device?.makeCommandQueue()
    static let state: MTLRenderPipelineState? = {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: ferroShaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "ferroVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "ferroFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            FileHandle.standardError.write(Data("liquid-bar: ferrofluid shader: \(error)\n".utf8))
            return nil
        }
    }()
}

/// A transparent Metal layer that draws one frame of ferrofluid when asked, and nothing otherwise.
final class FerroView: NSView {
    private let metal = CAMetalLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        metal.device = FerroPipeline.device
        metal.pixelFormat = .bgra8Unorm
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.contentsScale = 2
        metal.presentsWithTransaction = false
        layer = metal
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    var onWindow: () -> Void = {}

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onWindow() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        metal.contentsScale = window?.backingScaleFactor ?? 2
    }

    func draw(_ frame: FluidFrame) {
        let scale = metal.contentsScale
        let pixels = CGSize(width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
        guard pixels.width > 0, pixels.height > 0, let state = FerroPipeline.state, let queue = FerroPipeline.queue else { return }
        if metal.drawableSize != pixels { metal.drawableSize = pixels }
        guard let drawable = metal.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        // Away from any tinted bead the rim reflects a cool, neutral sky.
        var header = Header(size: SIMD2(Float(frame.width), Float(frame.height)), scale: Float(scale), inset: Float(frame.inset),
                            tint: SIMD4(0.55, 0.62, 0.75, 0.6), beads: Int32(frame.beads.count), spikes: Int32(frame.spikes.count))
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&header, length: MemoryLayout<Header>.stride, index: 0)
        for (index, array) in [frame.beads, frame.spikes, frame.tints].enumerated() {
            var data = array.isEmpty ? [SIMD4<Float>.zero] : array
            encoder.setFragmentBytes(&data, length: MemoryLayout<SIMD4<Float>>.stride * data.count, index: index + 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
