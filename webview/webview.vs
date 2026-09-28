package webview

import (
    "image/draw"
    "ui/window"
    "web"
    "web/html"
)

/// A web page inside a window: the part of the window it covers, the
/// window's events turned into the page's input, the page's cursor, the
/// system clipboard, and navigation -- files, and pages from the network
/// with what they refer to, history, and what links lead to
/// (navigation.vs). The page itself -- styles, layout, forms, selection
/// -- is `Page`, a `web.Page`, which needs no window.
///
/// Everything here runs on the main thread, where the window is.
@MainActor
public final class WebView {
    /// The page this view shows.
    public let Page: web.Page

    var origin: window.Point
    var size: window.Size

    // Navigation (navigation.vs).
    var url: string = ""
    var history: [string] = []
    var position: int = -1
    var visited = Set<string>()
    var loads = 0
    var loading = false
    var onLoadStarted: ((string) -> Void)? = nil
    var onLoadFinished: ((LoadReport) -> Void)? = nil
    var onNeedsDisplay: (() -> Void)? = nil
    /// Where "about:home" goes, and "" does: a file path or URL.
    public var StartPage: string = ""
    /// A folder each page from the network is recorded into, with what it
    /// refers to, for web/cmd/snapshot --archive to show offline.
    public var RecordInto: string? = nil

    public init(page: web.Page? = nil) {
        if let p = page {
            Page = p
        } else {
            Page = web.Page()
        }
        origin = window.Point(0, 0)
        size = window.Size(800, 600)
        Page.Clipboard = SystemClipboard()
        Page.SetViewportSize(draw.Size(size.Width, size.Height))
        // Links lead where they point, and :visited knows where the view
        // has been. A host that handles navigation itself sets its own.
        Page.OnNavigate { target in self.Navigate(target) }
        Page.IsVisited { u in self.visited.contains(u) }
    }

    /// Where the view sits in the window, and how big it is, in points.
    public func SetBounds(origin: window.Point, size: window.Size) {
        self.origin = origin
        self.size = size
        Page.SetViewportSize(draw.Size(size.Width, size.Height))
    }

    public func Bounds() -> (origin: window.Point, size: window.Size) {
        return (origin: origin, size: size)
    }

    /// Takes a window event: pointer events inside the view's bounds,
    /// scrolling, and keys while something in the page has focus are
    /// handled; the rest is ignored and left to the host.
    public func Handle(_ event: window.Event) -> web.EventResult {
        guard let input = Input(event) else { return .ignored }
        return Page.Handle(input)
    }

    /// The page's input for a window event, in the page's coordinates;
    /// nil for events a page doesn't take.
    public func Input(_ event: window.Event) -> web.Input? {
        switch event {
        case .pointerMoved(let p):
            return .pointerMoved(local(p.Position))
        case .pointerDown(let p, let button):
            return .pointerDown(web.Pointer(local(p.Position), button: pageButton(button), clicks: p.Clicks))
        case .pointerUp(let p, let button):
            return .pointerUp(web.Pointer(local(p.Position), button: pageButton(button), clicks: p.Clicks))
        case .pointerLeft:
            return .pointerLeft
        case .scrolled(let s):
            return .wheel(web.Wheel(draw.Point(s.Delta.X, s.Delta.Y), precise: s.Precise))
        case .keyDown(let k):
            return .keyDown(web.Key(Key: k.Key, Code: CodeName(k.Code), Shift: k.Modifiers.Shift,
                                    Control: k.Modifiers.Control, Alt: k.Modifiers.Alt, Meta: k.Modifiers.Meta))
        case .text(let t):
            return .text(t)
        default:
            return nil
        }
    }

    /// The element under a point in the window, or nil.
    public func ElementAt(_ p: window.Point) -> html.Node? {
        return Page.ElementAt(local(p))
    }

    func local(_ p: window.Point) -> draw.Point {
        return draw.Point(p.X - origin.X, p.Y - origin.Y)
    }

    /// Paints the page into the window's pixels at the view's bounds.
    public func Draw(into pixels: inout [uint8], canvasSize: window.PixelSize, scale: float32) {
        Page.Draw(into: &pixels, width: canvasSize.Width, height: canvasSize.Height, scale: scale, at: draw.Point(origin.X, origin.Y))
    }

    public func NeedsRepaint() -> bool { return Page.NeedsRepaint() }
    public func NeedsAnimation() -> bool { return Page.NeedsAnimation() }
    public func Advance(time: float64) -> bool { return Page.Advance(time: time) }

    /// The window cursor for what the pointer is over.
    public func DesiredCursor() -> window.Cursor {
        switch Page.DesiredCursor() {
        case .pointer: return window.Cursor.pointingHand
        case .text: return window.Cursor.iBeam
        case .crosshair: return window.Cursor.crosshair
        case .ewResize: return window.Cursor.resizeLeftRight
        case .nsResize: return window.Cursor.resizeUpDown
        case .default: return window.Cursor.arrow
        }
    }
}

func pageButton(_ b: window.PointerButton) -> web.PointerButton {
    switch b {
    case .primary: return .primary
    case .secondary: return .secondary
    case .middle: return .middle
    case .other: return .other
    }
}

/// The system clipboard, for a page's copy and paste.
struct SystemClipboard: web.Clipboard {
    func ReadText() -> string { return window.ClipboardText() }
    func WriteText(_ text: string) { window.SetClipboardText(text) }
}

/// A key's W3C `KeyboardEvent.code` name: "KeyA", "Digit1", "ArrowLeft".
public func CodeName(_ code: window.KeyCode) -> string {
    switch code {
    case .unknown: return "Unidentified"
    case .a: return "KeyA"
    case .b: return "KeyB"
    case .c: return "KeyC"
    case .d: return "KeyD"
    case .e: return "KeyE"
    case .f: return "KeyF"
    case .g: return "KeyG"
    case .h: return "KeyH"
    case .i: return "KeyI"
    case .j: return "KeyJ"
    case .k: return "KeyK"
    case .l: return "KeyL"
    case .m: return "KeyM"
    case .n: return "KeyN"
    case .o: return "KeyO"
    case .p: return "KeyP"
    case .q: return "KeyQ"
    case .r: return "KeyR"
    case .s: return "KeyS"
    case .t: return "KeyT"
    case .u: return "KeyU"
    case .v: return "KeyV"
    case .w: return "KeyW"
    case .x: return "KeyX"
    case .y: return "KeyY"
    case .z: return "KeyZ"
    case .digit0: return "Digit0"
    case .digit1: return "Digit1"
    case .digit2: return "Digit2"
    case .digit3: return "Digit3"
    case .digit4: return "Digit4"
    case .digit5: return "Digit5"
    case .digit6: return "Digit6"
    case .digit7: return "Digit7"
    case .digit8: return "Digit8"
    case .digit9: return "Digit9"
    case .escape: return "Escape"
    case .enter: return "Enter"
    case .tab: return "Tab"
    case .space: return "Space"
    case .backspace: return "Backspace"
    case .delete: return "Delete"
    case .arrowLeft: return "ArrowLeft"
    case .arrowRight: return "ArrowRight"
    case .arrowUp: return "ArrowUp"
    case .arrowDown: return "ArrowDown"
    case .home: return "Home"
    case .end: return "End"
    case .pageUp: return "PageUp"
    case .pageDown: return "PageDown"
    case .shiftLeft: return "ShiftLeft"
    case .shiftRight: return "ShiftRight"
    case .controlLeft: return "ControlLeft"
    case .controlRight: return "ControlRight"
    case .altLeft: return "AltLeft"
    case .altRight: return "AltRight"
    case .metaLeft: return "MetaLeft"
    case .metaRight: return "MetaRight"
    case .capsLock: return "CapsLock"
    case .f1: return "F1"
    case .f2: return "F2"
    case .f3: return "F3"
    case .f4: return "F4"
    case .f5: return "F5"
    case .f6: return "F6"
    case .f7: return "F7"
    case .f8: return "F8"
    case .f9: return "F9"
    case .f10: return "F10"
    case .f11: return "F11"
    case .f12: return "F12"
    case .minus: return "Minus"
    case .equal: return "Equal"
    case .bracketLeft: return "BracketLeft"
    case .bracketRight: return "BracketRight"
    case .backslash: return "Backslash"
    case .semicolon: return "Semicolon"
    case .quote: return "Quote"
    case .backquote: return "Backquote"
    case .comma: return "Comma"
    case .period: return "Period"
    case .slash: return "Slash"
    }
}
