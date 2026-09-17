package window

/// Where a key is on the keyboard, whatever the layout says it means: the
/// key labelled W on a US keyboard is `.w` under AZERTY too, where it types
/// Z. What a game binds, and what a shortcut should not.
///
/// The W3C calls this `KeyboardEvent.code`. What the key means is
/// `KeyEvent.Key`, and what it types arrives as `.text`.
public enum KeyCode: int32 {
    case unknown = 0
    case a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 8, i = 9
    case j = 10, k = 11, l = 12, m = 13, n = 14, o = 15, p = 16, q = 17
    case r = 18, s = 19, t = 20, u = 21, v = 22, w = 23, x = 24, y = 25, z = 26
    case digit0 = 27, digit1 = 28, digit2 = 29, digit3 = 30, digit4 = 31
    case digit5 = 32, digit6 = 33, digit7 = 34, digit8 = 35, digit9 = 36
    case escape = 40, enter = 41, tab = 42, space = 43, backspace = 44, delete = 45
    case arrowLeft = 46, arrowRight = 47, arrowUp = 48, arrowDown = 49
    case home = 50, end = 51, pageUp = 52, pageDown = 53
    case shiftLeft = 60, shiftRight = 61, controlLeft = 62, controlRight = 63
    case altLeft = 64, altRight = 65, metaLeft = 66, metaRight = 67, capsLock = 68
    case f1 = 70, f2 = 71, f3 = 72, f4 = 73, f5 = 74, f6 = 75
    case f7 = 76, f8 = 77, f9 = 78, f10 = 79, f11 = 80, f12 = 81
    case minus = 90, equal = 91, bracketLeft = 92, bracketRight = 93, backslash = 94
    case semicolon = 95, quote = 96, backquote = 97, comma = 98, period = 99, slash = 100
}

/// The modifier keys held down.
public struct Modifiers {
    public var Shift: bool
    public var Control: bool
    public var Alt: bool
    /// Command on a Mac, the Windows key elsewhere.
    public var Meta: bool
    public var CapsLock: bool

    public init() {
        Shift = false
        Control = false
        Alt = false
        Meta = false
        CapsLock = false
    }
}

// modifiersFrom reads cwindow's modifier bits.
func modifiersFrom(_ bits: int32) -> Modifiers {
    var m = Modifiers()
    m.Shift = bits & 1 != 0
    m.Control = bits & 2 != 0
    m.Alt = bits & 4 != 0
    m.Meta = bits & 8 != 0
    m.CapsLock = bits & 16 != 0
    return m
}
