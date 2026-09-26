# ui

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![ui: window | webview](https://img.shields.io/badge/ui-window%20%7C%20webview-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/ui)
[![runtime: async](https://img.shields.io/badge/runtime-async-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Screens and input: native windows, and web pages shown in them.

What a window shows comes from packages that need no window: the
rasterizer is `image/draw`, fonts are `text/font`, and the HTML and CSS
engine is the `web` repository. A headless program renders with those
and never links a window system.

---

## Quick Start

Run any program in `cmd/` directly with `vsc run`:

```bash
# The browser: an address bar, history, and the web engine's sample pages.
vsc run browser

# Interactive window examples.
vsc run hello
vsc run paint

# The checks.
vsc run check-webview
vsc run lifecycle
```

---

## Packages

| Package | What it is | Native code |
| :--- | :--- | :--- |
| **`ui/window`** | A native window: creation, an async event queue, a frame clock, a pixel surface, cursors, the clipboard. | `window.cpp` (`ui.window`): Cocoa in `window_darwin.mm`, NativeActivity in `window_android.cpp` |
| **`ui/webview`** | A `web.Page` in a window: the part of the window it covers, the window's events turned into the page's input, the page's cursor, and the system clipboard. | none |

---

## The webview

```vertex
package main

import (
    "ui/webview"
    "ui/window"
)

@MainActor
func main() async -> int32 {
    let win = try! window.Create(title: "Docs", size: window.Size(900, 700))
    let surface = win.Surface()

    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 0), size: win.Size())
    try! view.Page.LoadFile("docs/index.html")
    view.Page.OnNavigate { url in try? view.Page.LoadFile(url); win.RequestFrame() }

    var pixels = [uint8](repeating: 0, count: int(win.PixelSize().Width) * int(win.PixelSize().Height) * 4)
    win.RequestFrame()
    while let event = await win.WaitEvent() {
        switch event {
        case .closeRequested:
            win.Close()
            return 0
        case .frame(_):
            view.Draw(into: &pixels, canvasSize: win.PixelSize(), scale: win.ScaleFactor())
            try? surface.Present(pixels, size: win.PixelSize())
        default:
            if view.Handle(event) == .handled || view.NeedsRepaint() { win.RequestFrame() }
            win.SetCursor(view.DesiredCursor())
        }
    }
    return 0
}
```

`WebView` is `@MainActor`, like the window it lives in. The page it
shows is `view.Page`: loading, styles, layout, forms and selection are
the `web` repository's, and work the same without a window.

| | |
| :--- | :--- |
| `WebView(page:)`, `Page` | The view, and the `web.Page` it shows. |
| `SetBounds(origin:size:)`, `Bounds()` | Where the view is in the window, in points. |
| `Handle(_:)` | Take a window event: `.handled` or `.ignored`. |
| `Input(_:)` | The page input a window event becomes, in the page's coordinates. |
| `Draw(into:canvasSize:scale:)` | Paint into the window's pixels at the view's bounds. |
| `DesiredCursor()` | The window cursor for what the pointer is over. |
| `ElementAt(_:)` | The element under a point in the window. |
| `NeedsRepaint()`, `NeedsAnimation()`, `Advance(time:)` | What the host should do next. |
| `CodeName(_:)` | A key's W3C `KeyboardEvent.code` name. |

---

## License

[MIT](LICENSE)
