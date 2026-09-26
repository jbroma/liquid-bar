import AppKit
import LiquidBarCore
import Metal
import MetalKit
import QuartzCore

/// The ferrofluid shader, compiled from source at launch: the offline Metal compiler is an optional Xcode download,
/// the runtime compiler ships with macOS.
let ferroShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Header {
    float2 size;       // view size in points
    float scale;       // pixels per point
    float inset;       // glass wall thickness
    float4 tint;       // light colour away from tinted beads
    float2 envOrigin;  // wallpaper uv at the view's top-left corner
    float2 envScale;   // wallpaper uv per point
    int beads;
    int spikes;
    int hasEnv;
    int pad;
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

static float wall(float2 p, constant Header &u) {
    float r = u.size.y / 2 - u.inset;
    float2 c = float2(clamp(p.x, u.size.y / 2, u.size.x - u.size.y / 2), u.size.y / 2);
    return length(p - c) - r;
}

static float field(float2 p, constant Header &u, constant float4 *beads, constant float4 *spikes) {
    float d = 1e5;
    for (int i = 0; i < u.beads; i++) d = smin(d, capsule(p, beads[i]), 9.0);
    for (int i = 0; i < u.spikes; i++) d = smin(d, spike(p, spikes[i]), 2.5);
    // The glass holds it: nothing crosses the vessel's inner wall.
    return max(d, wall(p, u));
}

// The colour of light near p: each bead's content colour close to it, a neutral sky elsewhere.
static float3 tintAt(float2 p, constant Header &u, constant float4 *beads, constant float4 *tints) {
    float3 sum = u.tint.rgb * 0.3;
    float weight = 0.3;
    for (int i = 0; i < u.beads; i++) {
        float w = exp(-max(capsule(p, beads[i]), 0.0) / 6) * tints[i].a;
        sum += tints[i].rgb * w;
        weight += w;
    }
    return sum / weight;
}

// Where p sits along the nearest bead, -1 at its left end to 1 at its right.
static float alongBead(float2 p, constant Header &u, constant float4 *beads) {
    float best = 1e5, along = 0;
    for (int i = 0; i < u.beads; i++) {
        float d = capsule(p, beads[i]);
        if (d < best) { best = d; along = clamp((p.x - beads[i].x) / max(beads[i].z, 1.0), -1.0, 1.0); }
    }
    return along;
}

fragment float4 ferroFragment(VOut in [[stage_in]], constant Header &u [[buffer(0)]], constant float4 *beads [[buffer(1)]],
                              constant float4 *spikes [[buffer(2)]], constant float4 *tints [[buffer(3)]],
                              texture2d<float> env [[texture(0)]]) {
    constexpr sampler mirror(address::mirrored_repeat, filter::linear, mip_filter::linear);
    float2 p = in.position.xy / u.scale;
    float d = field(p, u, beads, spikes);
    float alpha = clamp(0.5 - d * u.scale, 0.0, 1.0);
    // Where the fluid touches the glass it darkens it a little, like a wet contact line.
    float contact = 0.16 * exp(-max(d, 0.0) / 2.0) * clamp(-wall(p, u) * u.scale, 0.0, 1.0);
    if (alpha <= 0) return float4(0, 0, 0, contact);

    // A domed body: its height rises as a quarter ellipse from the rim to the middle, so the silhouette is a wall
    // turning away from the viewer and only the centre line faces it.
    float h = 0.3;
    float2 g = float2(field(p + float2(h, 0), u, beads, spikes) - field(p - float2(h, 0), u, beads, spikes),
                      field(p + float2(0, h), u, beads, spikes) - field(p - float2(0, h), u, beads, spikes));
    float2 outward = length(g) > 0.0001 ? normalize(g) : float2(0, -1);
    // The dome is as deep as the fluid is thick here, measured inward and crosswise, so a thin spike, even seen end
    // on, gets a centre line facing the viewer like a bead does instead of being all mirror rim.
    float2 across = float2(-outward.y, outward.x);
    float inward = 25, sideA = 25, sideB = 25;
    for (int i = 8; i >= 1; i--) {
        float t = 1.6 * i;
        if (field(p - outward * t, u, beads, spikes) > 0) inward = t;
        if (field(p + across * t, u, beads, spikes) > 0) sideA = t;
        if (field(p - across * t, u, beads, spikes) > 0) sideB = t;
    }
    float radius = clamp(0.5 * min(inward, sideA + sideB), 1.5, 12.5);
    float x = clamp(-d / radius, 0.0, 1.0);
    float slope = min((1 - x) / max(sqrt(1 - (1 - x) * (1 - x)), 0.03), 30.0) * 1.3;
    float3 n = normalize(float3(outward * slope, 1));
    // Screen y points down, so a surface facing up has negative n.y.
    float up = -n.y;
    // Black oil reflects like a dielectric: little facing the viewer, a mirror toward the silhouette.
    float fresnel = 0.03 + 0.97 * pow(1 - n.z, 3.0);

    // Mercury reflects the room, not the point behind it: the rim facing up shows the wallpaper above the bar, the
    // rim facing down a dim floor, split by a crisp horizon. Sharp at the silhouette, blurred where it faces us.
    float3 sky = u.tint.rgb * 0.5;
    if (u.hasEnv != 0) {
        float2 uv = u.envOrigin + (p + n.xy * 40.0) * u.envScale;
        sky = env.sample(mirror, uv, level(0.8 + 3.5 * n.z)).rgb;
    }
    float horizon = smoothstep(-0.14, 0.0, up);
    float3 world = mix(sky * 0.14, sky * (0.95 + 0.4 * up), horizon);
    // The content's colour glints in the floor reflection just under the horizon, never as a fill.
    float3 light = tintAt(p, u, beads, tints);
    float glint = exp(-pow((up + 0.3) / 0.14, 2.0));
    world += light * glint * 0.8;

    // One softbox up and to the left: a soft window across the upper left of each bead, as a light of finite size
    // lands on a capsule seen from nearby.
    float along = alongBead(p, u, beads);
    float box = smoothstep(0.4, 0.5, up) * (1 - smoothstep(0.68, 0.78, up))
              * smoothstep(-1.0, -0.7, along) * (1 - smoothstep(-0.25, 0.35, along));
    // Thin crisp arcs where the surface curves fastest: a ring just inside the silhouette of the rounded ends, lit on
    // the upper left and, fainter, the lower right, like the rim of Liquid Glass.
    float ring = exp(-pow((n.z - 0.35) / 0.1, 2.0));
    float spec = ring * (smoothstep(0.85, 0.98, dot(outward, float2(-0.8, -0.6)))
                         + 0.4 * smoothstep(0.85, 0.98, dot(outward, float2(0.8, 0.6))));

    // The vessel's front glass lies over the fluid: its bright hairline where the wall curves away at the top shows
    // over the black.
    float fromTop = (p.y - u.inset) / (u.size.y - 2 * u.inset);
    float hairline = 0.16 * exp(-abs(wall(p, u) + 0.8) * 2.4) * (1 - smoothstep(0.15, 0.4, fromTop));

    float3 color = float3(0.003, 0.003, 0.004) * (1 - fresnel)
                 + world * fresnel
                 + float3(box * 0.16)
                 + float3(spec * 0.7)
                 + float3(hairline);
    // Ordered dither keeps the dark gradients from banding.
    uint2 pix = uint2(in.position.xy) % 4;
    const float bayer[16] = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5};
    color += (bayer[pix.y * 4 + pix.x] / 16.0 - 0.5) / 255.0;
    float a = alpha + contact * (1 - alpha);
    return float4(min(max(color, 0.0), 1.0) * alpha, a);
}
"""

private struct Header {
    var size: SIMD2<Float>
    var scale: Float
    var inset: Float
    var tint: SIMD4<Float>
    var envOrigin: SIMD2<Float>
    var envScale: SIMD2<Float>
    var beads: Int32
    var spikes: Int32
    var hasEnv: Int32
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

/// The desktop picture of each screen as a small mipmapped texture, for the fluid to reflect. Loaded once per picture.
@MainActor
enum Wallpaper {
    private static var cache: [URL: MTLTexture] = [:]
    /// Posted when a screen's picture may have changed; fluid views redraw with the new reflection.
    static let changed = Notification.Name("dev.liquidbar.wallpaper")
    #if DEBUG
    /// A stand-in picture for captures on other backdrops.
    static var override: URL?
    #endif

    static func texture(for screen: NSScreen) -> MTLTexture? {
        var url = NSWorkspace.shared.desktopImageURL(for: screen)
        #if DEBUG
        url = override ?? url
        #endif
        guard let url, let device = FerroPipeline.device else { return nil }
        if let texture = cache[url] { return texture }
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // A quarter of a 4K picture is plenty for a blurred reflection.
        let width = 1024, height = max(1, Int(Double(width) * Double(image.height) / Double(image.width)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage(),
              let texture = try? MTKTextureLoader(device: device).newTexture(cgImage: small, options: [.generateMipmaps: true, .SRGB: false])
        else { return nil }
        cache[url] = texture
        return texture
    }

    /// The wallpaper uv at a screen point (top-left origin within the screen), for a picture that fills the screen.
    static func mapping(texture: MTLTexture, screen: CGSize) -> (origin: CGPoint, perPoint: CGSize) {
        let image = CGSize(width: texture.width, height: texture.height)
        let fill = max(screen.width / image.width, screen.height / image.height)
        let shown = CGSize(width: image.width * fill, height: image.height * fill)
        let offset = CGPoint(x: (shown.width - screen.width) / 2, y: (shown.height - screen.height) / 2)
        return (CGPoint(x: offset.x / shown.width, y: offset.y / shown.height), CGSize(width: 1 / shown.width, height: 1 / shown.height))
    }
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
        // Where this view sits on its screen's wallpaper.
        var origin = SIMD2<Float>(0, 0), perPoint = SIMD2<Float>(0, 0)
        let screen = window?.screen
        let env = screen.flatMap(Wallpaper.texture)
        if let screen, let env, let window {
            let rect = window.convertToScreen(convert(bounds, to: nil))
            let map = Wallpaper.mapping(texture: env, screen: screen.frame.size)
            let topLeft = CGPoint(x: rect.minX - screen.frame.minX, y: screen.frame.maxY - rect.maxY)
            origin = SIMD2(Float(map.origin.x + topLeft.x * map.perPoint.width), Float(map.origin.y + topLeft.y * map.perPoint.height))
            perPoint = SIMD2(Float(map.perPoint.width), Float(map.perPoint.height))
        }
        var header = Header(size: SIMD2(Float(frame.width), Float(frame.height)), scale: Float(scale), inset: Float(frame.inset),
                            tint: SIMD4(0.62, 0.68, 0.8, 1), envOrigin: origin, envScale: perPoint,
                            beads: Int32(frame.beads.count), spikes: Int32(frame.spikes.count), hasEnv: env == nil ? 0 : 1)
        encoder.setRenderPipelineState(state)
        encoder.setFragmentBytes(&header, length: MemoryLayout<Header>.stride, index: 0)
        for (index, array) in [frame.beads, frame.spikes, frame.tints].enumerated() {
            var data = array.isEmpty ? [SIMD4<Float>.zero] : array
            encoder.setFragmentBytes(&data, length: MemoryLayout<SIMD4<Float>>.stride * data.count, index: index + 1)
        }
        encoder.setFragmentTexture(env, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
