# ui/webview

A `web.Page` in a window: the part of the window it covers, the window's events turned into the page's input, the page's cursor, and the system clipboard.

```vertex
import "ui/webview"
```

## Types

- **`LoadReport`** (struct): What a load brought back, and what the engine couldn't use: the list of what a site still needs.
- **`WebView`** (class)

## Functions

- `func CodeName(_ code: window.KeyCode) -> string`: A key's W3C `KeyboardEvent.code` name: "KeyA", "Digit1", "ArrowLeft".

Part of the [`ui`](https://github.com/vertex-language/ui) repository.
