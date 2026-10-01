# ui/window

A native window: creation, an async event queue, a frame clock, a pixel surface, cursors, the clipboard.

## Example

```vertex
import "ui/window"

let win = try window.Create(title: "Hello")
while let event = await win.WaitEvent() {
    if case .closeRequested = event { break }
}
```

## Types

- **`WindowError`** (enum): Every way an operation in this package fails.
- **`Event`** (enum): Something that happened to a window.
- **`KeyEvent`** (struct): A key press or release.
- **`Pointer`** (struct): A mouse, a pen or a finger.
- **`PointerKind`** (enum)
- **`PointerButton`** (enum)
- **`Scroll`** (struct): A scroll gesture's movement.
- **`Frame`** (struct): When a frame will be shown.
- **`Theme`** (enum)
- **`Size`** (struct): A size in points: what a window is measured in, and what input arrives in.
- and 10 more

## Functions

- `func SetClipboardText(_ text: string)`: Puts text on the system clipboard, replacing what was there.
- `func ClipboardText() -> string`: The text on the system clipboard, or "" where it holds none.
- `func Blit( source: borrowing [uint8], sourceSize: PixelSize, destination: inout [uint8], destinationSize: PixelSize, at origin: Point, scale: float32 = 1.0 )`: Copies a rectangular block of premultiplied RGBA8 pixels from `source` into `destination`.
- `func Create(title: string, size: Size = Size(1280, 720), options: Options = .default) throws -> Window`: Makes a window with a title and a content size in points, centred on the main display.
- `func Window.Surface() -> Surface`: The window's surface.
- `func Surface.Present(_ pixels: borrowing [uint8], size: PixelSize) throws`: Shows pixels: `size.Width * size.Height` of them, four bytes each -- red, green, blue, alpha, premultiplied -- top row first.
- `func Surface.SetScaling(_ mode: ScalingMode)`: Sets the surface content scaling mode.
- `func Surface.RawParts() -> (kind: SurfaceKind, window: uint64, view: uint64)`: The native objects behind the surface, for a renderer that binds its own swapchain to them and for nothing else.
- `func Window.WaitEvent() async -> Event?`: Waits for the next event and returns it, or nil once the window is closed.
- `func Window.PollEvent() -> Event?`: The next event if one is already queued, and nil if none is. Never waits.
- and 14 more

Part of the [`ui`](https://github.com/vertex-language/ui) repository.
