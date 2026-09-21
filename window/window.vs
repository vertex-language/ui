package window

import cwindow

/// How a window is made, for the cases where the defaults are not wanted.
public struct Options {
    /// The user can resize it. On by default.
    public var Resizable: bool = true
    /// It has a title bar and a border. On by default.
    public var Decorated: bool = true
    /// It is shown as soon as it is made. On by default.
    public var Visible: bool = true
    /// The smallest content size the user can resize it to.
    public var MinSize: Size? = nil

    public init() {}

    /// What `Create` uses when it is not given anything else.
    public static let `default` = Options()
}

/// A native window.
///
/// Waiting for what happens to it is `async`: `WaitEvent` parks the task it
/// is called on until the window has an event, and everything else the
/// program has going runs meanwhile, on the same thread. Everything else here
/// is immediate.
///
/// A window does not close itself. `.closeRequested` asks; `Close` does it.
public struct Window {
    /// The window's number, for code that has to reach past this package.
    public let Id: int32
}

/// Makes a window with a title and a content size in points, centred on the
/// main display.
///
/// Must be called from the program's main thread, which is where `main` and
/// its tasks run.
public func Create(title: string, size: Size = Size(1280, 720),
                   options: Options = .default) throws -> Window {
    var flags: int32 = 0
    if options.Resizable { flags |= 1 }
    if options.Decorated { flags |= 2 }
    if options.Visible { flags |= 4 }
    let id = cwindow_create(title, float64(size.Width), float64(size.Height), flags)
    if id < 0 {
        throw errorFor(id, "creating a window titled \"\(title)\"")
    }
    if let min = options.MinSize {
        cwindow_set_min_size(id, float64(min.Width), float64(min.Height))
    }
    return Window(Id: id)
}

// MARK: - Events

/// Waits for the next event and returns it, or nil once the window is
/// closed.
///
/// On a task this parks that task: other tasks run, and the thread sleeps in
/// the window system's own wait when nothing at all can run.
public func (w: borrowing Window) WaitEvent() async -> Event? {
    while true {
        let kind = cwindow_next(w.Id)
        if kind < 0 {
            return nil
        }
        if kind > 0 {
            if let e = decode(w.Id, kind) {
                return e
            }
            continue
        }
        let fd = cwindow_descriptor(w.Id)
        if fd < 0 {
            return nil
        }
        _ = await waitFd(fd, 1, -1)
    }
}

/// The next event if one is already queued, and nil if none is. Never waits.
public func (w: borrowing Window) PollEvent() -> Event? {
    while true {
        let kind = cwindow_next(w.Id)
        if kind <= 0 {
            return nil
        }
        if let e = decode(w.Id, kind) {
            return e
        }
    }
}

/// Asks for one `.frame` event, at the display's next refresh. Ask again
/// from the frame to keep animating; stop asking to stop.
public func (w: borrowing Window) RequestFrame() {
    cwindow_request_frame(w.Id)
}

// MARK: - Geometry and state

/// The content area's size in points.
public func (w: borrowing Window) Size() -> Size {
    return Size(float32(cwindow_width(w.Id)), float32(cwindow_height(w.Id)))
}

/// The content area's size in device pixels: what to size pixels for.
public func (w: borrowing Window) PixelSize() -> PixelSize {
    return PixelSize(cwindow_pixel_width(w.Id), cwindow_pixel_height(w.Id))
}

/// Device pixels per point on the display the window is on.
public func (w: borrowing Window) ScaleFactor() -> float32 {
    return float32(cwindow_scale(w.Id))
}

/// The appearance the window is drawn in.
public func (w: borrowing Window) Theme() -> Theme {
    return cwindow_theme(w.Id) == 1 ? .dark : .light
}

/// Whether keyboard input goes to this window.
public func (w: borrowing Window) Focused() -> bool {
    return cwindow_focused(w.Id) == 1
}

// MARK: - Changing it

public func (w: borrowing Window) SetTitle(_ title: string) {
    cwindow_set_title(w.Id, title)
}

/// Resizes the content area, in points.
public func (w: borrowing Window) SetSize(_ size: Size) {
    cwindow_set_size(w.Id, float64(size.Width), float64(size.Height))
}

public func (w: borrowing Window) SetMinSize(_ size: Size) {
    cwindow_set_min_size(w.Id, float64(size.Width), float64(size.Height))
}

public func (w: borrowing Window) SetVisible(_ visible: bool) {
    cwindow_set_visible(w.Id, visible ? 1 : 0)
}

public func (w: borrowing Window) SetFullscreen(_ fullscreen: bool) {
    cwindow_set_fullscreen(w.Id, fullscreen ? 1 : 0)
}

/// The system mouse cursor shape.
public enum Cursor: Equatable {
    case arrow
    case pointingHand
    case iBeam
    case crosshair
    case resizeLeftRight
    case resizeUpDown
    /// No cursor over this window.
    case hidden
}

/// Changes the mouse cursor shape when hovered over this window.
public func (w: borrowing Window) SetCursor(_ cursor: Cursor) {
    var c: int32 = 0
    switch cursor {
    case .arrow: c = 0
    case .pointingHand: c = 1
    case .iBeam: c = 2
    case .crosshair: c = 3
    case .resizeLeftRight: c = 4
    case .resizeUpDown: c = 5
    case .hidden: c = 6
    }
    cwindow_set_cursor(w.Id, c)
}

/// Shows a cursor drawn by the program over this window: `width * height`
/// pixels, four bytes each -- red, green, blue, alpha, premultiplied -- top
/// row first, `scale` pixels per point (2 for pixels drawn for Retina),
/// with the click point at pixel (hotX, hotY). It stays until the next
/// `SetCursor` or `SetCursorImage`.
public func (w: borrowing Window) SetCursorImage(_ pixels: borrowing [uint8], width: int32, height: int32,
                                                  hotX: int32, hotY: int32, scale: float32 = 1) throws {
    let want = int(width) * int(height) * 4
    if width <= 0 || height <= 0 || pixels.count != want {
        throw WindowError.invalidArgument(
            "\(pixels.count) bytes for a \(width)x\(height) cursor, which wants \(want)")
    }
    let rc = pixels.withUnsafeBufferPointer { bp in
        cwindow_set_cursor_image(w.Id, bp.baseAddress, width, height, hotX, hotY, float64(scale))
    }
    if rc < 0 {
        throw errorFor(rc, "setting a \(width)x\(height) cursor")
    }
}

/// Closes the window. It is consumed: nothing can be asked of it afterwards,
/// and a task waiting on it gets nil.
public func (w: consuming Window) Close() {
    cwindow_close(w.Id)
}
