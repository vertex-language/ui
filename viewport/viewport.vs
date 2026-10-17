// Package viewport is a box in a .vsx page that a program draws into
// itself: a 3D view, a video, a canvas of its own. It reserves its box in
// the page's layout like any element, styled and sized by the page's
// CSS; each frame the host asks its Draw for pixels of the box's size and
// puts them there, over what the page painted.
//
//     viewport.Viewport(class: "preview", live: true) { w, h, t in renderer.Frame(…) }
//
// It knows nothing about scenes: it only hands out a size and takes back
// pixels (proposed_graphics_v3.md §5.10). What the page paints over the
// box (a toolbar, a status line positioned on top) is painted again over
// each frame, so overlays work; the page itself is painted only when it
// changes. ui/app is its host; another host
// calls Composite after drawing the page.
package viewport

import (
    "image/draw"
    "ui/component"
    "web"
    "web/html"
    "web/layout"
)

/// Draw makes a frame of a viewport: given its size in device pixels and
/// the frame's time in seconds, answers RGBA pixels, top row first.
public typealias Draw = (int, int, float64) -> [uint8]

final class entry {
    var node: html.Node? = nil
    let draw: Draw
    var live: bool
    var dirty = true
    /// Where the box was last drawn, in CSS pixels from the viewport's
    /// corner (the page's scroll taken off).
    var x: float32 = 0
    var y: float32 = 0
    var w: float32 = 0
    var h: float32 = 0

    init(_ draw: Draw, live: bool) {
        self.draw = draw
        self.live = live
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

/// Handle is a viewport, for asking it to redraw.
public final class Handle {
    let e: entry

    init(_ e: entry) {
        self.e = e
    }

    /// Invalidate asks for a new frame from this viewport.
    public func Invalidate() {
        e.dirty = true
        waker?()
    }

    /// Where the viewport was last drawn, in CSS pixels from the page
    /// viewport's corner: what pointer events' X and Y are measured from.
    public var Origin: (X: float32, Y: float32) {
        return (X: e.x, Y: e.y)
    }

    /// Its size when last drawn, in CSS pixels.
    public var Size: (Width: float32, Height: float32) {
        return (Width: e.w, Height: e.h)
    }

    /// Live is whether it's redrawn every frame (an animation) or only
    /// when invalidated.
    public var Live: bool {
        get { return e.live }
        set { e.live = newValue }
    }
}

/// Viewport is the element: a div with the given class, drawn by `draw`.
/// `handle`, when given, is told the viewport's Handle.
public func Viewport(class: string = "viewport", live: bool = false, handle: ((Handle) -> void)? = nil, _ draw: Draw) -> component.Node {
    let e = entry(draw, live: live)
    entries.append(e)
    handle?(Handle(e))
    return component.Element("div", [component.Attribute.Static("class", `class`),
                                     component.Attribute.Static("data-viewport", ""),
                                     component.Attribute(.ref({ n in
                                         e.node = n
                                         e.dirty = true
                                         if n == nil { entries = entries.filter { $0 !== e } }
                                     }))], [])
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
        let px = e.draw(w, h, time)
        e.dirty = false
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
