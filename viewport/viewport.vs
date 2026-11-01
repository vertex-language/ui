// Package viewport is a box in a .vsx page that something else fills: a
// web view, a remote desktop, a virtual machine's screen, a canvas, a 3D
// view, a terminal. The box is laid out, styled and sized by the page's
// CSS like any element; a Source makes its pixels at the box's size each
// frame it wants one, and is given what the user does in the box.
//
//     <Viewport source={screen} class="screen" focusable />
//
// What the page paints over the box (a toolbar, a status line positioned
// on top) is painted again over each frame, so overlays work; the page
// itself is painted only when it changes. ui/app is the host: on the GPU
// where the platform has one (Accelerator, accel.vs), and otherwise it
// calls Composite after drawing the page, as componenttest does. A source
// draws with Draw (pixels, which every host takes) and, to skip the copy
// through the host on the GPU, DrawTexture.
package viewport

import (
    "gpu"
    "image/draw"
    "ui/component"
    "ui/state"
    "web"
    "web/dom"
    "web/html"
    "web/layout"
)

/// One frame a source is asked for: its box's size in device pixels, the
/// device pixels to a CSS pixel, and the frame's time in seconds.
public struct Frame {
    public let Width: int
    public let Height: int
    public let Scale: float32
    public let Time: float64

    public init(width: int, height: int, scale: float32, time: float64) {
        Width = width
        Height = height
        Scale = scale
        Time = time
    }
}

/// What fills a viewport. A subclass overrides Draw, and what else it
/// takes: pointer positions are in CSS pixels from the box's corner.
/// Everything is called on the UI thread: a source is @MainActor, and so
/// is a subclass of it.
@MainActor
open class Source {
    public init() {}

    /// The frame's RGBA pixels, premultiplied, top row first, Width ×
    /// Height of them. Fewer leaves the box as the page painted it.
    open func Draw(_ frame: Frame) -> [uint8] { return [] }

    /// The frame drawn on the GPU, where the host draws with one: a
    /// texture on `device`, Width × Height, premultiplied RGBA, shown in
    /// the box with no copy through the host. Nil (the default) has the
    /// host take Draw's pixels instead. A source that overrides this
    /// still answers Draw, which is what a host without a GPU shows.
    open func DrawTexture(_ frame: Frame, device: gpu.Device) -> gpu.Texture? { return nil }

    /// The source is in the document, in the box `handle` is; Detached,
    /// it is not, and is drawn no more.
    open func Attached(_ handle: Handle) {}
    open func Detached() {}

    open func PointerDown(_ e: dom.PointerEvent, x: float32, y: float32) {}
    open func PointerMove(_ e: dom.PointerEvent, x: float32, y: float32) {}
    open func PointerUp(_ e: dom.PointerEvent, x: float32, y: float32) {}
    open func PointerLeave() {}
    open func Wheel(_ e: dom.WheelEvent, x: float32, y: float32) {}
    open func KeyDown(_ e: dom.KeyboardEvent) {}
    open func KeyUp(_ e: dom.KeyboardEvent) {}
    /// Text typed while the box has the keyboard, after the keyboard
    /// layout and input method: `e.Data`.
    open func Text(_ e: dom.InputEvent) {}
    /// An input method composing text while the box has the keyboard:
    /// compositionstart, compositionupdate (`e.Data`, what it has so far),
    /// compositionend; what it commits comes as Text.
    open func Composition(_ e: dom.CompositionEvent) {}
    /// The box took the keyboard, or lost it.
    open func Focus(_ focused: bool) {}
}

/// A source that only draws, through a function of the frame's width,
/// height (device pixels) and time.
@MainActor
public final class Drawing: Source {
    let draw: (int, int, float64) -> [uint8]

    public init(_ draw: @escaping (int, int, float64) -> [uint8]) {
        self.draw = draw
        super.init()
    }

    public override func Draw(_ frame: Frame) -> [uint8] {
        return draw(frame.Width, frame.Height, frame.Time)
    }
}

final class entry {
    var source: Source
    var node: html.Node? = nil
    var live: bool
    var dirty = true
    /// The cursor the source asks for over the box, as CSS names it.
    var cursor = state.Signal<string>("")
    /// Where the box was last drawn, in CSS pixels from the page
    /// viewport's corner (the page's scroll taken off).
    var x: float32 = 0
    var y: float32 = 0
    var w: float32 = 0
    var h: float32 = 0

    init(_ source: Source, live: bool) {
        self.source = source
        self.live = live
    }

    /// p, a position in the page, from the box's corner.
    func local(_ px: float32, _ py: float32) -> (float32, float32) {
        if let n = node, let r = component.Bounds(of: n) { return (px - r.X, py - r.Y) }
        return (px - x, py - y)
    }
}

// Used from the UI thread only, like the page it belongs to.
var entries: [entry] = []

// What the host gave to be told a viewport wants a frame: an Invalidate
// from a task (data that arrived) has no event to ride on.
var waker: (() -> void)? = nil

/// SetWaker gives the host's way of asking for a frame, which Invalidate
/// calls, so a viewport invalidated outside an event (by a task) is drawn.
/// ui/app sets it.
public func SetWaker(_ wake: (() -> void)?) {
    waker = wake
}

/// Handle is a source's view of its box: to ask for a frame, to know where
/// the box is, to set the pointer's shape over it, and to take the
/// keyboard.
public final class Handle {
    let e: entry

    init(_ e: entry) {
        self.e = e
    }

    /// Asks for a new frame from the source.
    public func Invalidate() {
        e.dirty = true
        waker?()
    }

    /// Where the box was last drawn, in CSS pixels from the page
    /// viewport's corner: what a page's pointer events are measured from.
    public var Origin: (X: float32, Y: float32) {
        return (X: e.x, Y: e.y)
    }

    /// The box's size when last drawn, in CSS pixels.
    public var Size: (Width: float32, Height: float32) {
        return (Width: e.w, Height: e.h)
    }

    /// Whether the source is drawn every frame (an animation, a video) or
    /// only when invalidated.
    public var Live: bool {
        get { return e.live }
        set {
            e.live = newValue
            if newValue { waker?() }
        }
    }

    /// The pointer's shape over the box, as CSS names it: "default",
    /// "pointer", "text", "crosshair", "ew-resize", "ns-resize"; "" for
    /// what the page's styles say.
    public var Cursor: string {
        get { return e.cursor.Peek() }
        set {
            var c = e.cursor
            c.Value = newValue
        }
    }

    /// Gives the box the keyboard.
    public func Focus() {
        if let n = e.node { component.Focus(n) }
    }
}

/// Viewport is the element a source fills: a div with the given class,
/// drawn by `source`, given the pointer over it and, `focusable`, the
/// keyboard once clicked. `live` draws it every frame.
///
///     <Viewport source={screen} class="screen" live />
@MainActor
public func Viewport(source: Source, class: string = "viewport", live: bool = false, focusable: bool = false) -> component.Node {
    let cls = `class`
    return component.Call("viewport.Viewport", { box(source, cls, live, focusable) })
}

/// The viewport's body, rendered by its own fiber: its entry is made once
/// and ends with it.
@MainActor
func box(_ source: Source, _ cls: string, _ live: bool, _ focusable: bool) -> component.Node {
    let held = component.useRef<entry>(nil)
    if held.current == nil { held.current = entry(source, live: live) }
    let e = held.current!
    e.live = live
    component.useEffect({
        entries.append(e)
        e.source.Attached(Handle(e))
        waker?()
        return {
            entries = entries.filter { $0 !== e }
            e.source.Detached()
        }
    }, [])
    // Another source given in the same place takes the box over.
    component.useEffect({
        if e.source !== source {
            e.source.Detached()
            e.source = source
            e.dirty = true
            source.Attached(Handle(e))
            waker?()
        }
    })
    var attrs: [component.Attribute] = [
        component.Attribute.Static("class", cls),
        component.Attribute.Static("data-viewport", ""),
        component.Attribute(.liveText("style", {
            let c = e.cursor.Value
            return c.isEmpty ? nil : "cursor: " + c
        })),
        component.Attribute(.ref({ n in
            e.node = n
            e.dirty = true
        })),
        component.Attribute.On("pointerdown", dom.PointerEvent.self, { ev in
            if focusable, let n = e.node { component.Focus(n) }
            let (x, y) = e.local(ev.X, ev.Y)
            e.source.PointerDown(ev, x: x, y: y)
        }),
        component.Attribute.On("pointermove", dom.PointerEvent.self, { ev in
            let (x, y) = e.local(ev.X, ev.Y)
            e.source.PointerMove(ev, x: x, y: y)
        }),
        component.Attribute.On("pointerup", dom.PointerEvent.self, { ev in
            let (x, y) = e.local(ev.X, ev.Y)
            e.source.PointerUp(ev, x: x, y: y)
        }),
        // The engine tells of the pointer leaving as mouseleave.
        component.Attribute.On("mouseleave", dom.MouseEvent.self, { _ in e.source.PointerLeave() }),
        component.Attribute.On("wheel", dom.WheelEvent.self, { ev in
            let (x, y) = e.local(ev.X, ev.Y)
            e.source.Wheel(ev, x: x, y: y)
        }),
        component.Attribute.On("keydown", dom.KeyboardEvent.self, { ev in e.source.KeyDown(ev) }),
        component.Attribute.On("keyup", dom.KeyboardEvent.self, { ev in e.source.KeyUp(ev) }),
        component.Attribute.On("beforeinput", dom.InputEvent.self, { ev in e.source.Text(ev) }),
        component.Attribute.On("compositionstart", dom.CompositionEvent.self, { ev in e.source.Composition(ev) }),
        component.Attribute.On("compositionupdate", dom.CompositionEvent.self, { ev in e.source.Composition(ev) }),
        component.Attribute.On("compositionend", dom.CompositionEvent.self, { ev in e.source.Composition(ev) }),
        component.Attribute.On("focus", dom.FocusEvent.self, { _ in e.source.Focus(true) }),
        component.Attribute.On("blur", dom.FocusEvent.self, { _ in e.source.Focus(false) }),
    ]
    if focusable { attrs.append(component.Attribute.Static("tabindex", "0")) }
    return component.Element("div", attrs, [])
}

/// Wanted is whether any viewport in the page wants a frame: a live one,
/// or one invalidated since it was last drawn.
public func Wanted() -> bool {
    for e in entries where e.node != nil && (e.live || e.dirty) { return true }
    return false
}

/// Composite draws the page's viewports into the pixels the page was
/// drawn into (canvas size in device pixels, scale device pixels per CSS
/// pixel), each clipped to the canvas. With all false only the ones that
/// want a frame (live, or invalidated) are drawn; the host passes true
/// when it has just painted the page over them. Answers whether it drew
/// any.
@MainActor
@discardableResult
public func Composite(_ page: web.Page, _ pixels: inout [uint8], width: int, height: int, scale: float32, time: float64,
                      all: bool = true) -> bool {
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
        let px = e.source.Draw(Frame(width: w, height: h, scale: scale, time: time))
        drew = true
        if px.count < w * h * 4 { continue }
        blit(px, w, h, into: &pixels, width, height, at: x0, y0)
        // What the page paints over the box (toolbars, labels) goes back
        // on top.
        page.DrawOver(n, into: &pixels, width: int32(width), height: int32(height), scale: scale,
                      clip: draw.IRect(int32(x0), int32(y0), int32(w), int32(h)))
    }
    return drew
}

// blit copies a w × h RGBA image into a canvas at (x, y), clipped, a row
// at a time with memcpy (a byte loop costs a hundred times more).
func blit(_ src: [uint8], _ w: int, _ h: int, into dst: inout [uint8], _ cw: int, _ ch: int, at x: int, _ y: int) {
    let cx0 = max(0, x), cy0 = max(0, y), cx1 = min(cw, x + w), cy1 = min(ch, y + h)
    if cx1 <= cx0 || cy1 <= cy0 { return }
    let span = (cx1 - cx0) * 4
    dst.withUnsafeMutableBytes { d in
        src.withUnsafeBytes { s in
            guard let db = d.baseAddress, let sb = s.baseAddress else { return }
            for row in cy0..<cy1 {
                (db + (row * cw + cx0) * 4).copyMemory(from: sb + ((row - y) * w + (cx0 - x)) * 4, byteCount: span)
            }
        }
    }
}
