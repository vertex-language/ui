package webview

import (
    "image/draw"
    "ui/component"
    "ui/viewport"
    "web"
    "web/dom"
)

/// A web view as a component: a page shown in a box of the .vsx page
/// around it, laid out and styled like any element, taking the pointer
/// and, once clicked, the keyboard.
///
///     <webview.View url="https://example.com" class="web" />
///     <webview.View controller={view} />        // a WebView the program steers
///
/// `controller` is the WebView it shows, for navigation and the page;
/// without one it makes its own. `url`, when given, is navigated to, and
/// again whenever it changes. `onLoad` hears each load that finishes.
@MainActor
public func View(url: string = "", controller: WebView? = nil, class: string = "webview",
                 onLoad: ((LoadReport) -> void)? = nil) -> component.Node {
    let cls = `class`
    return component.Call("webview.View", { viewBody(url, controller, cls, onLoad) })
}

@MainActor
func viewBody(_ url: string, _ controller: WebView?, _ cls: string, _ onLoad: ((LoadReport) -> void)?) -> component.Node {
    let source = component.useMemo({ PageSource(controller ?? WebView()) }, [])
    source.onLoad = onLoad
    component.useEffect({
        if !url.isEmpty { source.view.Navigate(url) }
    }, [url])
    return viewport.Viewport(source: source, class: cls, focusable: true)
}

/// A WebView's page as a viewport's source: drawn at the box's size, given
/// what the user does in the box, and drawn again when it changes.
@MainActor
final class PageSource: viewport.Source {
    let view: WebView
    var handle: viewport.Handle? = nil
    var onLoad: ((LoadReport) -> void)? = nil
    var width: float32 = 0
    var height: float32 = 0

    init(_ view: WebView) {
        self.view = view
        super.init()
        view.OnNeedsDisplay { self.changed() }
        view.OnLoadFinished { report in
            self.changed()
            if let h = self.onLoad { h(report) }
        }
    }

    override func Attached(_ handle: viewport.Handle) {
        self.handle = handle
        handle.Invalidate()
    }

    override func Detached() {
        handle = nil
    }

    func changed() {
        handle?.Invalidate()
    }

    override func Draw(_ f: viewport.Frame) -> [uint8] {
        let w = float32(f.Width) / f.Scale
        let h = float32(f.Height) / f.Scale
        if w != width || h != height {
            width = w
            height = h
            view.Page.SetViewportSize(draw.Size(w, h))
        }
        _ = view.Page.Advance(time: f.Time)
        var px = [uint8](repeating: 0, count: f.Width * f.Height * 4)
        view.Page.Draw(into: &px, width: int32(f.Width), height: int32(f.Height), scale: f.Scale)
        // A blinking caret wants frames while it blinks.
        handle?.Live = view.Page.NeedsAnimation()
        return px
    }

    /// Gives the page an input; what it took stops at the box.
    func send(_ input: web.Input, _ e: dom.Event) {
        let r = view.Page.Handle(input)
        if r == .handled {
            e.PreventDefault()
            e.StopPropagation()
        }
        handle?.Cursor = view.Page.DesiredCursor().CSSName
        if r == .handled || view.Page.NeedsRepaint() { changed() }
    }

    override func PointerDown(_ e: dom.PointerEvent, x: float32, y: float32) {
        send(.pointerDown(pointer(e, x, y)), e)
    }

    override func PointerMove(_ e: dom.PointerEvent, x: float32, y: float32) {
        send(.pointerMoved(draw.Point(x, y)), e)
    }

    override func PointerUp(_ e: dom.PointerEvent, x: float32, y: float32) {
        send(.pointerUp(pointer(e, x, y)), e)
    }

    override func PointerLeave() {
        _ = view.Page.Handle(.pointerLeft)
        handle?.Cursor = ""
        changed()
    }

    override func Wheel(_ e: dom.WheelEvent, x: float32, y: float32) {
        _ = view.Page.Handle(.pointerMoved(draw.Point(x, y)))
        send(.wheel(web.Wheel(draw.Point(e.DeltaX, e.DeltaY),
                              modifiers: web.Modifiers(shift: e.Shift, control: e.Control, alt: e.Alt, meta: e.Meta))), e)
    }

    override func KeyDown(_ e: dom.KeyboardEvent) {
        send(.keyDown(web.Key(Key: e.Key, Code: e.Code, Shift: e.Shift, Control: e.Control, Alt: e.Alt, Meta: e.Meta)), e)
    }

    override func KeyUp(_ e: dom.KeyboardEvent) {
        send(.keyUp(web.Key(Key: e.Key, Code: e.Code, Shift: e.Shift, Control: e.Control, Alt: e.Alt, Meta: e.Meta)), e)
    }

    override func Composition(_ e: dom.CompositionEvent) {
        switch e.Type {
        case "compositionupdate": send(.composition(e.Data), e)
        case "compositionend": if e.Data.isEmpty { send(.composition(""), e) }
        default: break
        }
    }

    override func Text(_ e: dom.InputEvent) {
        if e.Data.isEmpty { return }
        send(.text(e.Data), e)
    }
}

/// A page's pointer press from a box's pointer event, at x, y in the box.
func pointer(_ e: dom.PointerEvent, _ x: float32, _ y: float32) -> web.Pointer {
    var button = web.PointerButton.primary
    switch e.Button {
    case 1: button = .middle
    case 2: button = .secondary
    case 0: button = .primary
    default: button = .other
    }
    return web.Pointer(draw.Point(x, y), button: button, clicks: e.Clicks,
                       modifiers: web.Modifiers(shift: e.Shift, control: e.Control, alt: e.Alt, meta: e.Meta))
}
