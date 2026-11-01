package viewport

// The GPU path for a page and its viewports, where the platform has one
// (Metal, on macOS): the page is a texture uploaded only when it is
// painted again, each viewport's frame lands in its box on the device --
// a source's texture drawn there with no copy through the host, or its
// pixels uploaded over just the box -- and what the page paints over the
// boxes is one overlay texture, made again only with the page. A gpu
// Layer shows them. Where there is no GPU (another platform, the CPU
// device, a window that can't take a layer) Accelerator.Make answers nil
// and the host draws with Composite on the CPU, as before.

import (
    "gpu"
    "image/draw"
    "os/env"
    "web"
    "web/layout"
)

/// A source's frame drawn into its box on the GPU: a full-box quad that
/// reads the source's texture texel for texel, written as it is (a
/// viewport's pixels replace the page's under them, as on the CPU).
let copySource = """
#include <metal_stdlib>
using namespace metal;
struct Out { float4 pos [[position]]; };
vertex Out viewportQuad(uint vid [[vertex_id]]) {
    Out o;
    float2 xy = float2((vid & 1) != 0 ? 1.0 : -1.0, (vid & 2) != 0 ? -1.0 : 1.0);
    o.pos = float4(xy, 0.0, 1.0);
    return o;
}
fragment float4 copy(Out in [[stage_in]], texture2d<float> t [[texture(0)]], constant float2& origin [[buffer(0)]]) {
    return t.read(uint2(in.pos.xy - origin));
}
"""

/// The GPU host of a window's page and viewports.
@MainActor
public final class Accelerator {
    public let Device: gpu.Device
    /// Nil offscreen: frames are made but not shown.
    let layer: gpu.Layer?
    var scene: gpu.Texture
    var overlay: gpu.Texture
    var overlayPixels: [uint8] = []
    var hasOverlay = false
    var width: int
    var height: int
    var copy: gpu.RenderPipeline? = nil
    var copyTried = false

    init(device: gpu.Device, layer: gpu.Layer?, scene: gpu.Texture, overlay: gpu.Texture, width: int, height: int) {
        Device = device
        self.layer = layer
        self.scene = scene
        self.overlay = overlay
        self.width = width
        self.height = height
    }

    /// Make lays a GPU layer over a window's native view (window.Surface's
    /// RawParts().view) for frames width × height pixels, or answers nil
    /// where there is no GPU to draw with: no Metal device, a view the
    /// layer can't attach to, or VSX_NO_GPU set in the environment. The
    /// host then draws on the CPU.
    public static func Make(view: uint64, width: int, height: int, scale: float64) -> Accelerator? {
        if (env.Get("VSX_NO_GPU") ?? "") != "" || view == 0 || width <= 0 || height <= 0 { return nil }
        let d = gpu.Default()
        if d.IsCPU { return nil }
        guard let scene = gpu.Texture.Create(device: d, width: width, height: height, format: .rgba8),
              let overlay = gpu.Texture.Create(device: d, width: width, height: height, format: .rgba8),
              let layer = gpu.Layer.Attach(device: d, view: view, width: width, height: height, scale: scale) else { return nil }
        return Accelerator(device: d, layer: layer, scene: scene, overlay: overlay, width: width, height: height)
    }

    /// Offscreen is an accelerator with no window: frames are composed
    /// on the device and read back with ReadBack, for tests and
    /// snapshots. Nil where there is no GPU.
    public static func Offscreen(width: int, height: int) -> Accelerator? {
        if width <= 0 || height <= 0 { return nil }
        let d = gpu.Default()
        if d.IsCPU { return nil }
        guard let scene = gpu.Texture.Create(device: d, width: width, height: height, format: .rgba8),
              let overlay = gpu.Texture.Create(device: d, width: width, height: height, format: .rgba8) else { return nil }
        return Accelerator(device: d, layer: nil, scene: scene, overlay: overlay, width: width, height: height)
    }

    /// Resize follows the window: new textures at its size, which the
    /// next frame fills (the host paints the page again after a resize).
    public func Resize(width: int, height: int, scale: float64) {
        if width <= 0 || height <= 0 { return }
        layer?.Resize(width: width, height: height, scale: scale)
        if width == self.width && height == self.height { return }
        guard let s = gpu.Texture.Create(device: Device, width: width, height: height, format: .rgba8),
              let o = gpu.Texture.Create(device: Device, width: width, height: height, format: .rgba8) else { return }
        scene = s
        overlay = o
        overlayPixels = []
        hasOverlay = false
        self.width = width
        self.height = height
    }

    /// Present shows the page and its viewports. pagePixels is the page as
    /// painted, width × height; with repainted it changed (or this is
    /// the first frame) and goes up to the device, every viewport is
    /// drawn again, and the overlay is made again. Otherwise only the
    /// viewports that want a frame are drawn. Answers whether anything
    /// was shown.
    @discardableResult
    public func Present(_ page: web.Page, pagePixels: [uint8], repainted: bool, scale: float32, time: float64) -> bool {
        if repainted {
            if pagePixels.count < width * height * 4 { return false }
            pagePixels.withUnsafeBytes { b in
                scene.Upload(x: 0, y: 0, width: width, height: height, bytes: b.baseAddress!, bytesPerRow: width * 4)
            }
            buildOverlay(page, scale: scale)
        }
        let drew = Draw(page, into: scene, width: width, height: height, scale: scale, time: time, all: repainted)
        if !repainted && !drew { return false }
        try? Device.Commit(wait: false)
        guard let l = layer else { return true }
        return l.Present(scene, overlay: hasOverlay ? overlay : nil)
    }

    /// Capture is what the last frame showed, read back: the page, its
    /// viewports and what is painted over them (a snapshot). Nil where
    /// the layer can't read back.
    public func Capture() -> [uint8]? {
        if let l = layer, let shown = l.Capture(scene, overlay: hasOverlay ? overlay : nil) { return shown }
        return ReadBack()
    }

    /// ReadBack is the composed frame read from the device: the scene,
    /// with the overlay put over it on the host. Width × Height RGBA.
    public func ReadBack() -> [uint8] {
        var out = [uint8](repeating: 0, count: width * height * 4)
        out.withUnsafeMutableBytes { b in scene.Read(x: 0, y: 0, width: width, height: height, into: b.baseAddress!, bytesPerRow: width * 4) }
        if !hasOverlay { return out }
        var over = [uint8](repeating: 0, count: width * height * 4)
        over.withUnsafeMutableBytes { b in overlay.Read(x: 0, y: 0, width: width, height: height, into: b.baseAddress!, bytesPerRow: width * 4) }
        var i = 0
        while i < out.count {
            let a = int(over[i + 3])
            if a == 255 {
                out[i] = over[i]; out[i + 1] = over[i + 1]; out[i + 2] = over[i + 2]; out[i + 3] = 255
            } else if a > 0 {
                var c = 0
                while c < 4 {
                    out[i + c] = uint8(min(255, int(over[i + c]) + (int(out[i + c]) * (255 - a) + 127) / 255))
                    c += 1
                }
            }
            i += 4
        }
        return out
    }

    /// What the page paints over the viewports' boxes, on a transparent
    /// ground, as one texture over the scene.
    func buildOverlay(_ page: web.Page, scale: float32) {
        let n = width * height * 4
        if overlayPixels.count != n { overlayPixels = [uint8](repeating: 0, count: n) }
        hasOverlay = false
        let scroll = page.ScrollOffset()
        for e in entries {
            guard let node = e.node, let box = page.BoxFor(node) else { continue }
            let pos = layout.PagePosition(box)
            let x0 = int(((pos.x - scroll.X) * scale).rounded()), y0 = int(((pos.y - scroll.Y) * scale).rounded())
            let w = int((box.Width * scale).rounded()), h = int((box.Height * scale).rounded())
            if w <= 0 || h <= 0 { continue }
            hasOverlay = true
            page.DrawOver(node, into: &overlayPixels, width: int32(width), height: int32(height), scale: scale,
                          clip: draw.IRect(int32(x0), int32(y0), int32(w), int32(h)))
        }
        if hasOverlay {
            overlayPixels.withUnsafeBytes { b in
                overlay.Upload(x: 0, y: 0, width: width, height: height, bytes: b.baseAddress!, bytesPerRow: width * 4)
            }
            // Ready for the next build: what was drawn is cleared again.
            overlayPixels = [uint8](repeating: 0, count: n)
        }
    }

    /// Draw puts the viewports' frames into their boxes in a texture the
    /// page's size (with all, every one; else those that want a frame),
    /// on the device. Answers whether it drew any. What Present does
    /// between uploading the page and showing it; a test calls it on a
    /// texture of its own.
    @discardableResult
    public func Draw(_ page: web.Page, into target: gpu.Texture, width: int, height: int, scale: float32, time: float64, all: bool) -> bool {
        let scroll = page.ScrollOffset()
        var drew = false
        for e in entries {
            guard let n = e.node else { continue }
            if !all && !e.live && !e.dirty { continue }
            guard let box = page.BoxFor(n) else { continue }
            let pos = layout.PagePosition(box)
            e.x = pos.x - scroll.X
            e.y = pos.y - scroll.Y
            e.w = box.Width
            e.h = box.Height
            let x0 = int(((pos.x - scroll.X) * scale).rounded()), y0 = int(((pos.y - scroll.Y) * scale).rounded())
            let w = int((box.Width * scale).rounded()), h = int((box.Height * scale).rounded())
            if w <= 0 || h <= 0 { continue }
            e.dirty = false
            drew = true
            let f = Frame(width: w, height: h, scale: scale, time: time)
            // The box within the target.
            let cx0 = max(0, x0), cy0 = max(0, y0), cx1 = min(width, x0 + w), cy1 = min(height, y0 + h)
            if cx1 <= cx0 || cy1 <= cy0 { continue }
            if let t = e.source.DrawTexture(f, device: Device), t.Width == w && t.Height == h {
                drawTexture(t, into: target, x: x0, y: y0, w: w, h: h, clip: (cx0, cy0, cx1 - cx0, cy1 - cy0))
                continue
            }
            let px = e.source.Draw(f)
            if px.count < w * h * 4 { continue }
            // Only the box's pixels go up, clipped to the target.
            px.withUnsafeBytes { b in
                let start = b.baseAddress! + ((cy0 - y0) * w + (cx0 - x0)) * 4
                target.Upload(x: cx0, y: cy0, width: cx1 - cx0, height: cy1 - cy0, bytes: start, bytesPerRow: w * 4)
            }
        }
        return drew
    }

    func drawTexture(_ t: gpu.Texture, into target: gpu.Texture, x: int, y: int, w: int, h: int, clip: (int, int, int, int)) {
        if !copyTried {
            copyTried = true
            do {
                let lib = try gpu.Library(device: Device, source: copySource)
                copy = try gpu.RenderPipeline(device: Device, vertex: try lib.Function("viewportQuad"), fragment: try lib.Function("copy"),
                                              gpu.PipelineDescriptor())
            } catch {
                print("viewport: the GPU copy didn't build: \(error)")
            }
        }
        guard let p = copy, let pass = gpu.RenderPass.Begin(device: Device, color: target, depth: nil) else { return }
        pass.SetPipeline(p)
        pass.SetViewport(x: float32(x), y: float32(y), width: float32(w), height: float32(h), near: 0, far: 1)
        pass.SetScissor(x: clip.0, y: clip.1, width: clip.2, height: clip.3)
        pass.SetTexture(fragment: true, t, index: 0)
        let origin: [float32] = [float32(x), float32(y)]
        origin.withUnsafeBytes { b in pass.SetBytes(fragment: true, b.baseAddress!, count: b.count, index: 0) }
        pass.Draw(primitive: 4, start: 0, count: 4, instances: 1)
        pass.End()
    }
}
