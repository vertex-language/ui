package window

/// Puts text on the system clipboard, replacing what was there.
public func SetClipboardText(text: string) {
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

/// Asks for files in the system's panel, and waits. accept is an <input>'s
/// (".png,image/*"). Empty where cancelled.
public func PickFiles(multiple: bool, accept: string) -> [string] {
    let n = winPickFiles(multiple ? 1 : 0, accept, nil, 0)
    if n <= 0 { return [] }
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        winPickFiles(0, accept, bp.baseAddress, int32(bp.count))
    }
    var out: [string] = []
    for line in string(cString: buf).split(separator: "\n") { out.append(string(line)) }
    return out
}

/// Asks for a date or time in a panel, and waits: type and value as an
/// <input>'s. Nil where cancelled.
public func PickDate(type: string, value: string) -> string? {
    let n = winPickDate(type, value, nil, 0)
    if n <= 0 { return nil }
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        winPickDate(type, value, bp.baseAddress, int32(bp.count))
    }
    return string(cString: buf)
}

/// Opens the color panel on a color (#rrggbb). Each change comes as a
/// colorPicked event to the window that has the keyboard.
public func PickColor(color: string) {
    winPickColor(color)
}
