# ui

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![ui: window](https://img.shields.io/badge/ui-window-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/ui)
[![runtime: async](https://img.shields.io/badge/runtime-async-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Standard user interface library for the Vertex programming language, providing native desktop windows, asynchronous event loops, and 60fps pixel buffer rendering.

---

## Packages

- **`ui/window`**: Native desktop windows (`window.Open`, `window.Window`, `window.Event`, `window.PixelBuffer`).

---

## Quick Start

```swift
package main

import "ui/window"

func main() async -> int32 {
    let win = try window.Open(title: "Vertex Window", width: 800, height: 600)
    print("Window opened: \(win.Title) (\(win.Width)x\(win.Height))")

    for await event in win.Events() {
        switch event {
        case .key(let key, let down):
            if down && key == 53 { // ESC
                win.Close()
            }
        case .closeRequested:
            win.Close()
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
# Run a window that prints lifecycle events
vsc run hello

# Run 60fps pixel buffer rendering with mouse drawing
vsc run paint

# Run headless/window lifecycle test
vsc run lifecycle
```

---

## License

[MIT](LICENSE)
