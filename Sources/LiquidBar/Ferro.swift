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
    float film;       // resting film height
    float filmFrom;   // film extent, grows out of the notch on launch
    float filmTo;
    float tintAmount;
    float4 tint;      // rim tint, straight alpha
    int mounds;
    int spikes;
    int ripples;
    int pad;
};

struct VOut { float4 position [[position]]; };

vertex VOut ferroVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    VOut out;
    out.position = float4(p * 2 - 1, 0, 1);
    return out;
}

static float plateau(float x, float c, float hw, float e) {
    float t = clamp((hw + e - abs(x - c)) / max(e, 0.001), 0.0, 1.0);
    return t * t * (3 - 2 * t);
}

static float smax(float a, float b, float k) {
    float h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}

// A mound of fluid: a flat top whose corners round off with radius `w`, standing `z` tall over half width `y`.
static float mound(float x, float4 m) {
    float r = min(m.w, m.z);
    float dx = max(0.0, abs(x - m.x) - (m.y - r));
    return dx >= r ? 0.0 : m.z - r + sqrt(r * r - dx * dx);
}

// Fluid height above the vessel's inner bottom at x.
static float surface(float x, constant Header &u, constant float4 *mounds, constant float4 *spikes, constant float4 *ripples) {
    float e = 5;
    float s = u.film * clamp((min(x - u.filmFrom, u.filmTo - x) + e) / e, 0.0, 1.0);
    for (int i = 0; i < u.mounds; i++) {
        s = smax(s, mound(x, mounds[i]), 4.0);
    }
    for (int i = 0; i < u.spikes; i++) {
        float4 k = spikes[i]; // x, height, half width, unused
        float t = max(0.0, 1 - abs(x - k.x) / k.z);
        s += k.y * t * t * (1.6 - 0.6 * t);
    }
    for (int i = 0; i < u.ripples; i++) {
        float4 r = ripples[i]; // origin, amplitude, wavelength, travelled distance
        float d = abs(x - r.x) - r.w;
        s += r.y * cos(6.2831 * d / r.z) * exp(-d * d / (r.z * r.z * 0.6));
    }
    return s;
}

// The rim tint at x: each mound's colour where it stands, the header's colour elsewhere.
static float4 tintAt(float x, constant Header &u, constant float4 *mounds, constant float4 *tints) {
    float4 sum = u.tint * u.tintAmount * 0.35;
    float weight = 0.35;
    for (int i = 0; i < u.mounds; i++) {
        float4 m = mounds[i];
        float w = clamp((m.y + 8 - abs(x - m.x)) / 8, 0.0, 1.0) * clamp(m.z / 6, 0.0, 1.0);
        sum += float4(tints[i].rgb * tints[i].a, tints[i].a) * w * 2;
        weight += w * 2;
    }
    return sum / weight;
}

static float capsuleSD(float2 p, float2 size, float inset) {
    float r = size.y / 2 - inset;
    float2 c = float2(clamp(p.x, size.y / 2, size.x - size.y / 2), size.y / 2);
    return length(p - c) - r;
}

// Depth inside the fluid in points: positive inside, negative outside.
static float depth(float2 p, constant Header &u, constant float4 *mounds, constant float4 *spikes, constant float4 *ripples) {
    float bottom = u.size.y - u.inset;
    float s = surface(p.x, u, mounds, spikes, ripples);
    float ds = (surface(p.x + 0.5, u, mounds, spikes, ripples) - surface(p.x - 0.5, u, mounds, spikes, ripples));
    float toSurface = (p.y - (bottom - s)) / sqrt(1 + ds * ds);
    return min(toSurface, -capsuleSD(p, u.size, u.inset));
}

fragment float4 ferroFragment(VOut in [[stage_in]], constant Header &u [[buffer(0)]], constant float4 *mounds [[buffer(1)]],
                              constant float4 *spikes [[buffer(2)]], constant float4 *ripples [[buffer(3)]],
                              constant float4 *tints [[buffer(4)]]) {
    float2 p = in.position.xy / u.scale;
    float d = depth(p, u, mounds, spikes, ripples);
    float alpha = clamp(d * u.scale + 0.5, 0.0, 1.0);
    if (alpha <= 0) return float4(0);
    // A rounded bevel along every edge gives the flat field a glossy, domed body.
    float h = 0.35;
    float2 g = float2(depth(p + float2(h, 0), u, mounds, spikes, ripples) - depth(p - float2(h, 0), u, mounds, spikes, ripples),
                      depth(p + float2(0, h), u, mounds, spikes, ripples) - depth(p - float2(0, h), u, mounds, spikes, ripples));
    float2 inward = length(g) > 0.0001 ? normalize(g) : float2(0, 1);
    float bevel = 4.5;
    float t = 1 - clamp(d / bevel, 0.0, 1.0);
    float3 n = normalize(float3(-inward * t, sqrt(max(0.0, 1 - t * t))));
    float3 v = float3(0, 0, 1);
    float3 key = normalize(float3(-0.5, -0.62, 0.6));   // y grows down, so light from above has negative y
    float3 fill = normalize(float3(0.7, -0.25, 0.67));
    float spec = pow(max(dot(n, normalize(key + v)), 0.0), 90.0) * 1.5 + pow(max(dot(n, normalize(fill + v)), 0.0), 30.0) * 0.16;
    float fresnel = pow(1 - n.z, 2.2);
    // The environment: a pale sky above, the dark desk below.
    float3 env = mix(float3(0.04, 0.04, 0.05), float3(0.6, 0.64, 0.72), clamp(0.5 - n.y * 0.8, 0.0, 1.0));
    float4 tint = tintAt(p.x, u, mounds, tints);
    float3 color = float3(0.01) + env * fresnel * 0.45 + tint.rgb * fresnel * 1.1 + spec;
    return float4(min(color, 1.0) * alpha, alpha);
}
"""

private struct Header {
    var size: SIMD2<Float>
    var scale: Float
    var inset: Float
    var film: Float
    var filmFrom: Float
    var filmTo: Float
    var tintAmount: Float
    var tint: SIMD4<Float>
    var mounds: Int32
    var spikes: Int32
    var ripples: Int32
    var pad: Int32 = 0
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
        // Away from any tinted mound the rim reflects a cool, neutral sky.
        var header = Header(size: SIMD2(Float(frame.width), Float(frame.height)), scale: Float(scale), inset: Float(frame.inset),
                            film: Float(frame.film), filmFrom: Float(frame.filmFrom), filmTo: Float(frame.filmTo), tintAmount: 0.5,
                            tint: SIMD4(0.55, 0.62, 0.75, 1),
                            mounds: Int32(frame.mounds.count), spikes: Int32(frame.spikes.count), ripples: Int32(frame.ripples.count))
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&header, length: MemoryLayout<Header>.stride, index: 0)
        for (index, array) in [frame.mounds, frame.spikes, frame.ripples, frame.tints].enumerated() {
            var data = array.isEmpty ? [SIMD4<Float>.zero] : array
            encoder.setFragmentBytes(&data, length: MemoryLayout<SIMD4<Float>>.stride * data.count, index: index + 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
