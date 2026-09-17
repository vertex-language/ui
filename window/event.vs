package window

/// Something that happened to a window.
public enum Event {
    /// The user asked to close the window: the close button, or Quit. A
    /// request -- nothing closes until the program calls `Close`, and a
    /// program with unsaved work is free not to.
    case closeRequested
    /// The window became, or stopped being, the one keyboard input goes to.
    case focusChanged(bool)

    /// The window's content area is this size now.
    case resized(Size)
    /// The window's top-left corner is here now, on its screen.
    case moved(Point)
    /// Device pixels per point changed: the window moved to another display.
    case scaleFactorChanged(float32)

    case pointerMoved(Pointer)
    case pointerDown(Pointer, PointerButton)
    case pointerUp(Pointer, PointerButton)
    /// The pointer left the window's content area.
    case pointerLeft
    case scrolled(Scroll)

    case keyDown(KeyEvent)
    case keyUp(KeyEvent)
    case modifiersChanged(Modifiers)
    /// Text the user typed, after the keyboard layout and any input method
    /// have had their say. Not one character per key: a dead key types
    /// nothing, and an input method commits a word at once.
    case text(string)
    /// Text an input method is composing and has not committed, to show in
    /// place; "" when composition ends.
    case composition(string)

    /// The display is about to show a frame: draw it now. Delivered once per
    /// `RequestFrame`.
    case frame(Frame)
    /// The system appearance changed.
    case themeChanged(Theme)
}

/// A key press or release.
public struct KeyEvent {
    /// Where the key is.
    public let Code: KeyCode
    /// What it means under the current layout, as the W3C writes it: "a",
    /// "A", "Enter", "ArrowLeft", "F5".
    public let Key: string
    public let Modifiers: Modifiers
    /// Whether this is the key repeating while it is held.
    public let Repeat: bool
}

/// A mouse, a pen or a finger.
public struct Pointer {
    /// In points, from the content area's top-left corner.
    public let Position: Point
    public let Kind: PointerKind
    /// 0 to 1 for a device that measures it, and 0 for one that does not.
    public let Pressure: float32
    public let Modifiers: Modifiers
}

public enum PointerKind {
    case mouse
    case pen
    case touch
}

public enum PointerButton {
    case primary
    case secondary
    case middle
    case other
}

/// A scroll gesture's movement.
public struct Scroll {
    /// How far, in points where `Precise` and in lines where not.
    public let Delta: Point
    /// A trackpad scrolls precisely; a wheel scrolls in lines.
    public let Precise: bool
    public let Modifiers: Modifiers
}

/// When a frame will be shown.
public struct Frame {
    /// The time the frame is for, in seconds on the system's monotonic
    /// clock -- what an animation should be computed at.
    public let Time: float64
    /// The display's current refresh interval, in seconds.
    public let Interval: float64
}

public enum Theme {
    case light
    case dark
}
