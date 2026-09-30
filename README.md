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
# The browser: an address bar, history, the web engine's sample pages, and
# the network (it prints what each site still needs).
vsc run browser
vsc run browser -- https://github.com

# Interactive window examples.
vsc run hello
vsc run paint

# A .vsx app: markup, state and handlers, in a window.
vsc run vsx-demo

# The checks.
vsc run check-webview
vsc run check-component
vsc run check-componenttest
vsc run lifecycle
```

---

## Packages

| Package | What it is | Native code |
| :--- | :--- | :--- |
| **`ui/window`** | A native window: creation, an async event queue, a frame clock, a pixel surface, cursors, the clipboard. | `window.cpp` (`ui.window`): Cocoa in `window_darwin.mm`, NativeActivity in `window_android.cpp` |
| **`ui/webview`** | A `web.Page` in a window: the part of the window it covers, the window's events turned into the page's input, the page's cursor, and the system clipboard. | none |
| **`ui/component`** | What `.vsx` markup lowers to (`Element`, `Attribute`, `Fragment`, `For`, `Node`), and `Mount`, which puts a root into a `dom.Document` and patches it when a signal it read changes. | none |
| **`ui/app`** | `app.Run`: a window whose page holds a mounted `.vsx` root, with events reaching its handlers. | none |
| **`ui/componenttest`** | Headless tests of components: queries by role, label and text, input through the page, computed styles, pixel goldens. | none |
| **`ui/kit`** | A few styled components, and the example of a library with `.vss` styles and tokens. | none |

---

## A .vsx app

Markup in a `.vsx` file is Vertex with JSX (the design is `proposed_vsx.md`).
A component is a function; state is `@reactive.State`; a handler is the
braces in an `on…` attribute.

```vsx
package main

import (
    "reactive"
    "ui/app"
    "ui/component"
    "web/dom"
)

func Counter(start: int = 0) -> Node {
    @reactive.State var count = start
    return <button onClick={count += 1}>Clicked {count} times</button>
}

func main() async -> int32 {
    return await app.Run(title: "Counter", width: 360, height: 200) { <Counter start={5} /> }
}
```

A click reaches the button through the page's own events (`web/dom`), the
handler writes `count`, and the root is rendered again and the page
patched in place once the event is done. `vsc run vsx-demo -- --snapshot
out.png` draws the first frame to a PNG and quits.

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
    view.OnLoadFinished { report in win.RequestFrame() }
    view.Navigate("https://github.com")      // or a file path; links are followed

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

`WebView` is `@MainActor`, like the window it lives in. It navigates:
files, and pages from the network fetched with the stylesheets and
images they refer to, a history, and links followed. The page it shows
is `view.Page`: styles, layout, forms and selection are the `web`
repository's, and work the same without a window.

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
| `Navigate(_:)`, `Back()`, `Forward()`, `Reload()` | Show an address: http(s) from the network, a path or file: URL from disk, "about:home" the `StartPage`. |
| `URL`, `IsLoading`, `CanGoBack`, `CanGoForward` | Where the view is. |
| `OnLoadStarted`, `OnLoadFinished` | A load's start, and its `LoadReport`: what came back, and what the engine couldn't use -- failed requests, images it can't decode, and the CSS it drops (`Text()` for a terminal). |
| `RecordInto` | A folder each network page is recorded into, for `web/cmd/snapshot --archive`. |
| `CodeName(_:)` | A key's W3C `KeyboardEvent.code` name. |

---

## License

[MIT](LICENSE)
