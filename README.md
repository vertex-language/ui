# ui

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![ui: window | draw | font | webview](https://img.shields.io/badge/ui-window%20%7C%20draw%20%7C%20font%20%7C%20webview-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/ui)
[![runtime: async](https://img.shields.io/badge/runtime-async-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

User interface packages: native windows, 2D rasterization, fonts, and an HTML/CSS layout and painting engine.

---

## Quick Start

Run any entry point with:

```bash
vsc run main.vs
```

---

## Packages

| Package | What it is | Native code |
| :--- | :--- | :--- |
| **`ui/window`** | A native window: creation, an async event queue, a frame clock, a pixel surface, cursors, the clipboard. | `window.cpp` (`ui.window`): Cocoa in `window_darwin.mm`, NativeActivity in `window_android.cpp` |
| **`ui/draw`** | A software rasterizer over premultiplied RGBA pixels: fills, anti-aliased rounded corners, borders, gradients, 8-bit masks, images resampled up or down. | none |
| **`ui/font`** | Faces by family, size, weight and slant; text shaped into glyphs with a per-word cache; glyph masks at any scale. | `font.cpp` (`ui.font`): CoreText in `font_darwin.mm` |
| **`ui/webview`** | HTML and CSS: the cascade, layout, painting, and input. | none |

Everything a page needs from the platform goes through `window`, `font` and
`image`; `draw` and `webview` draw into a plain `[uint8]` that `window.Surface.Present` shows.

---

## The webview

```vertex
package main

import "ui/window"
import "ui/webview"

func main() async -> int32 {
    let win = try window.Create(title: "Docs", size: window.Size(900, 700))
    let surface = win.Surface()

    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 0), size: win.Size())
    try view.LoadFile("docs/index.html")
    view.OnNavigate { url in try? view.LoadFile(url); win.RequestFrame() }

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
            if let cursor = view.DesiredCursor() { win.SetCursor(cursor) }
        }
    }
    return 0
}
```

`WebView` is `@MainActor`, like the window it lives in.

### What it renders

- **Style**: the cascade with specificity, `!important`, inheritance, `em`,
  `rem` and viewport units, `@media` queries, `@import`, `@font-face`,
  `:hover`, `:focus`, `:active`, `:visited` (the host says what was
  visited), `:nth-child()` and the rest of the selector family,
  `<link rel=stylesheet>`, `<base href>`, inline styles and presentational
  attributes, and a user agent stylesheet after the standard's rendering
  section. Pointer and keyboard state restyle only the elements whose
  rules ask about it.
- **Layout**: block flow with collapsing margins; inline formatting with
  white-space handling, line breaking at spaces and inside words where
  `overflow-wrap` allows, baseline alignment, `text-align` including
  `justify`, `text-overflow`;
  inline-blocks; images and form controls; floats and `clear`; flexbox rows and
  columns with wrap, grow, shrink, gaps and alignment; grid with fixed, fr
  and auto tracks, repeat() and auto-fill, spans and placement; tables with automatic
  column widths, colspan, row groups and captions; absolute, fixed, relative and
  sticky positioning; `overflow` clipping and scrolling; `calc()`.
- **Paint**: backgrounds with colors, gradients and images (sized, placed,
  tiled), rounded corners, borders in every style, box shadows, text with
  decorations, opacity, `visibility`, `z-index`, and a display list that
  scrolls without laying out again.
- **Input**: hover with cursors, links with a base URL, text editing in inputs
  and textareas with a blinking caret, check boxes, radios, selects, buttons, labels,
  `<details>`, form submission with its fields, Tab focus, keyboard scrolling,
  text selection with the mouse, copy and paste.

No JavaScript. The DOM (`text/html`) is the API: edit nodes and call
`Invalidate()`, and the page reflects the change.

### API

| | |
| :--- | :--- |
| `LoadHTML(_:baseURL:)`, `LoadFile(_:)` | Show a page; relative references resolve against the base. |
| `SetBounds(origin:size:)` | Where the view is in the window, in points. |
| `Draw(into:canvasSize:scale:)` | Paint into the window's pixels at the device scale. |
| `Handle(_:)` | Take a window event; `.handled` or `.ignored`. |
| `NeedsRepaint()`, `DesiredCursor()` | What the host should do next. |
| `NeedsAnimation()`, `Advance(time:)` | The caret blinks: keep frames coming while true. |
| `ScrollOffset()`, `SetScrollOffset(_:)`, `ScrollTo(_:)`, `ContentSize()` | Scrolling. |
| `OnNavigate`, `OnSubmit`, `OnAction`, `OnTitleChanged`, `OnHoverLink` | What the user did. |
| `IsVisited` | Which links the host has been to, for `:visited`. |
| `Document`, `Title`, `QuerySelector(_:)`, `ElementAt(_:)`, `BoxFor(_:)` | The page and its layout. |
| `Focus(_:)`, `FocusedElement`, `ValueOf(_:)` | Forms. |
| `SelectedText()`, `SelectAll()`, `ClearSelection()` | Selection. |
| `SetImage(_:_:)`, `Config.ResourceLoader` | Resources the host fetches. |

---

## Running

```bash
# The browser: an address bar, history, and the sample pages.
vsc run browser

# A page rendered to a PNG, without a window.
vsc run snapshot -- testdata/pages/home.html out.png 900 700 2

# The engine timed on a page: first frame, relayout, scroll, hover.
vsc run bench -- testdata/pages/docs.html

# The checks.
vsc run check-draw
vsc run check-font
vsc run check-webview
vsc run lifecycle

# The window examples.
vsc run hello
vsc run paint
```

---

## License

[MIT](LICENSE)
