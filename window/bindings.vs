package window

// The window system's C ABI is imported from cwindow's header; this file is
// the one thing that is not in it -- the runtime's wait -- and the helpers
// that turn cwindow's scalars into Vertex values.

import cwindow

// The runtime's wait on a descriptor. It is `async` because it suspends:
// given a task, it parks that task until the descriptor is readable and the
// executor runs everything else meanwhile. A window's descriptor is readable
// while the window has an event queued, so waiting for an event is this.
@_silgen_name("vertex_task_wait_fd")
func waitFd(_ fd: int32, _ events: int32, _ timeoutNanos: int64) async -> int32

// eventText is the current event's text.
func eventText(_ id: int32) -> string {
    let n = cwindow_event_text(id, nil, 0)
    var buf = [CChar](repeating: 0, count: int(n) + 1)
    _ = buf.withUnsafeMutableBufferPointer { bp in
        cwindow_event_text(id, bp.baseAddress, int32(bp.count))
    }
    return string(cString: buf)
}

// pointerOf is the current event's pointer.
func pointerOf(_ id: int32) -> Pointer {
    let kind: PointerKind = cwindow_event_flags(id) == 1 ? .pen : .mouse
    return Pointer(
        Position: Point(float32(cwindow_event_x(id)), float32(cwindow_event_y(id))),
        Kind: kind,
        Pressure: float32(cwindow_event_pressure(id)),
        Modifiers: modifiersFrom(cwindow_event_modifiers(id)))
}

// buttonOf is the current event's button.
func buttonOf(_ id: int32) -> PointerButton {
    switch cwindow_event_code(id) {
    case 0: return .primary
    case 1: return .secondary
    case 2: return .middle
    default: return .other
    }
}

// keyOf is the current event's key.
func keyOf(_ id: int32) -> KeyEvent {
    return KeyEvent(
        Code: KeyCode(rawValue: cwindow_event_code(id)) ?? .unknown,
        Key: eventText(id),
        Modifiers: modifiersFrom(cwindow_event_modifiers(id)),
        Repeat: cwindow_event_flags(id) == 1)
}

// decode turns the event cwindow_next just moved into the window's current
// slot into an Event, or nil for a kind this does not know.
func decode(_ id: int32, _ kind: int32) -> Event? {
    switch kind {
    case 1: return .closeRequested
    case 2: return .focusChanged(cwindow_event_code(id) == 1)
    case 3: return .resized(Size(float32(cwindow_event_x(id)), float32(cwindow_event_y(id))))
    case 4: return .moved(Point(float32(cwindow_event_x(id)), float32(cwindow_event_y(id))))
    case 5: return .scaleFactorChanged(float32(cwindow_event_x(id)))
    case 6: return .pointerMoved(pointerOf(id))
    case 7: return .pointerDown(pointerOf(id), buttonOf(id))
    case 8: return .pointerUp(pointerOf(id), buttonOf(id))
    case 9: return .pointerLeft
    case 10:
        return .scrolled(Scroll(
            Delta: Point(float32(cwindow_event_x(id)), float32(cwindow_event_y(id))),
            Precise: cwindow_event_code(id) == 1,
            Modifiers: modifiersFrom(cwindow_event_modifiers(id))))
    case 11: return .keyDown(keyOf(id))
    case 12: return .keyUp(keyOf(id))
    case 13: return .text(eventText(id))
    case 14: return .composition(eventText(id))
    case 15: return .frame(Frame(Time: cwindow_event_time(id), Interval: cwindow_event_interval(id)))
    case 16: return .themeChanged(cwindow_event_code(id) == 1 ? .dark : .light)
    case 17: return .modifiersChanged(modifiersFrom(cwindow_event_modifiers(id)))
    default: return nil
    }
}
