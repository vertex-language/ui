package window

/// Puts text on the system clipboard, replacing what was there.
public func SetClipboardText(_ text: string) {
    winSetClipboardText(text)
}

/// The text on the system clipboard, or "" where it holds none.
public func ClipboardText() -> string {
    let n = winClipboardText(nil, 0)
    if n <= 0 { return "" }
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        winClipboardText(bp.baseAddress, int32(bp.count))
    }
    return string(cString: buf)
}
