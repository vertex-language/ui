package window

// What window.cpp (module ui.window) does not say for itself -- the
// runtime's wait -- and the helpers that turn its scalars into Vertex
// values.

// The runtime's wait on a descriptor. It is `async` because it suspends:
// given a task, it parks that task until the descriptor is readable and the
// executor runs everything else meanwhile. A window's descriptor is readable
// while the window has an event queued, so waiting for an event is this.
@_silgen_name("vertex_task_wait_fd")
func waitFd(_ fd: int32, _ events: int32, _ timeoutNanos: int64) async -> int32

// eventText is the current event's text.
func eventText(_ id: int32) -> string {
    let n = winEventText(id, nil, 0)
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        winEventText(id, bp.baseAddress, int32(bp.count))
    }
    return string(cString: buf)
}

// pointerOf is the current event's pointer.
func pointerOf(_ id: int32) -> Pointer {
    let flags = winEventFlags(id)
    let kind: PointerKind = (flags & 255) == 1 ? .pen : .mouse
    let clicks = flags >> 8
    return Pointer(
        Position: Point(float32(winEventX(id)), float32(winEventY(id))),
        Kind: kind,
        Pressure: float32(winEventPressure(id)),
        Modifiers: modifiersFrom(winEventModifiers(id)),
        Clicks: clicks > 0 ? clicks : 1)
}

// buttonOf is the current event's button.
func buttonOf(_ id: int32) -> PointerButton {
    switch winEventCode(id) {
    case 0: return .primary
    case 1: return .secondary
    case 2: return .middle
    default: return .other
    }
}

// keyOf is the current event's key.
func keyOf(_ id: int32) -> KeyEvent {
    return KeyEvent(
        Code: KeyCode(rawValue: winEventCode(id)) ?? .unknown,
        Key: eventText(id),
        Modifiers: modifiersFrom(winEventModifiers(id)),
        Repeat: winEventFlags(id) == 1)
}

// decode turns the event winNext just moved into the window's current
// slot into an Event, or nil for a kind this does not know.
func decode(_ id: int32, _ kind: int32) -> Event? {
    switch kind {
    case 1: return .closeRequested
    case 2: return .focusChanged(winEventCode(id) == 1)
    case 3: return .resized(Size(float32(winEventX(id)), float32(winEventY(id))))
    case 4: return .moved(Point(float32(winEventX(id)), float32(winEventY(id))))
    case 5: return .scaleFactorChanged(float32(winEventX(id)))
    case 6: return .pointerMoved(pointerOf(id))
    case 7: return .pointerDown(pointerOf(id), buttonOf(id))
    case 8: return .pointerUp(pointerOf(id), buttonOf(id))
    case 9: return .pointerLeft
    case 10:
        return .scrolled(Scroll(
            Delta: Point(float32(winEventX(id)), float32(winEventY(id))),
            Precise: winEventCode(id) == 1,
            Modifiers: modifiersFrom(winEventModifiers(id))))
    case 11: return .keyDown(keyOf(id))
    case 12: return .keyUp(keyOf(id))
    case 13: return .text(eventText(id))
    case 14: return .composition(eventText(id))
    case 15: return .frame(Frame(Time: winEventTime(id), Interval: winEventInterval(id)))
    case 16: return .themeChanged(winEventCode(id) == 1 ? .dark : .light)
    case 17: return .modifiersChanged(modifiersFrom(winEventModifiers(id)))
    default: return nil
    }
}
