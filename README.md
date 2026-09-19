# ui

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![ui: window](https://img.shields.io/badge/ui-window-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/ui)
[![runtime: async](https://img.shields.io/badge/runtime-async-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Standard user interface library for the Vertex programming language, providing native desktop windows, asynchronous event loops, and 60fps pixel buffer rendering.

---

## Packages

- **`ui/window`**: Native desktop windows with async event queue and Cocoa OS integration (`window.Create`, `window.Window`, `window.Surface`, `window.SetCursor`).
- **`ui/webview`**: Pure Vertex software HTML/CSS rendering engine, block & inline layout, bitmap font rasterizer, hit testing, and CPU framebuffer painter (`webview.WebView`, `webview.Config`, `webview.Color`).

---

## Quick Start

### Embedded WebView

```vertex
package main

import "ui/window"
import "ui/webview"

func main() async -> int32 {
    let win = try window.Create(title: "Vertex Browser", size: window.Size(800, 600))
    let surface = win.Surface()

    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(800, 600))
    view.LoadHTML("""
    <html>
      <body style="margin: 20px; font-size: 16px; color: #24292f;">
        <h1 style="color: #0969da;">Hello from Vertex WebView!</h1>
        <p>Pure software HTML and CSS rendering engine in 100% pure Vertex.</p>
        <p><a href="https://vertex-lang.org">Clickable Hyperlink</a></p>
      </body>
    </html>
    """)

    view.OnNavigate { url in
        print("Navigated to: \(url)")
    }

    var pixels = [uint8](repeating: 255, count: 800 * 600 * 4)
    win.RequestFrame()

    while let event = await win.WaitEvent() {
        switch event {
        case .closeRequested:
            win.Close()
            return 0
        case .pointerMoved(_), .pointerDown(_, _), .scrolled(_):
            _ = view.Handle(event)
            if let cur = view.DesiredCursor() { win.SetCursor(cur) }
            win.RequestFrame()
        case .frame(_):
            let scale = win.ScaleFactor()
            view.Draw(into: &pixels, canvasSize: win.PixelSize(), scale: scale)
            try? surface.Present(pixels, size: win.PixelSize())
        default:
            break
        }
    }
    return 0
}
```

---

## Running

Execute examples or tests directly with `vsc`:

```bash
# Run full desktop HTML & CSS web browser example
vsc run browser

# Run automated headless webview test suite
vsc run check-webview

# Run a window that prints lifecycle events
vsc run hello

# Run 60fps pixel buffer rendering with mouse drawing
vsc run paint

# Run native window lifecycle verification test
vsc run lifecycle
```

---

## License

[MIT](LICENSE)
