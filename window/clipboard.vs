package window

import cwindow

/// Puts text on the system clipboard, replacing what was there.
public func SetClipboardText(_ text: string) {
    cwindow_set_clipboard_text(text)
}

/// The text on the system clipboard, or "" where it holds none.
public func ClipboardText() -> string {
    let n = cwindow_clipboard_text(nil, 0)
    if n <= 0 { return "" }
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        cwindow_clipboard_text(bp.baseAddress, int32(bp.count))
    }
    return string(cString: buf)
}
