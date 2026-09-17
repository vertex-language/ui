// A window that prints what happens to it. Close it, press Escape, or quit
// to end the program.
package main

import window

func describe(_ e: window.Event) -> string {
    switch e {
    case .closeRequested: return "close requested"
    case .focusChanged(let focused): return focused ? "focused" : "unfocused"
    case .resized(let s): return "resized to \(s.Width)x\(s.Height)"
    case .moved(let p): return "moved to \(p.X),\(p.Y)"
    case .scaleFactorChanged(let f): return "scale factor \(f)"
    case .pointerMoved(_): return ""
    case .pointerDown(let p, _): return "pointer down at \(p.Position.X),\(p.Position.Y)"
    case .pointerUp(_, _): return "pointer up"
    case .pointerLeft: return "pointer left"
    case .scrolled(let s): return "scrolled \(s.Delta.X),\(s.Delta.Y)"
    case .keyDown(let k): return "key down \(k.Key)\(k.Repeat ? " (repeat)" : "")"
    case .keyUp(let k): return "key up \(k.Key)"
    case .modifiersChanged(_): return ""
    case .text(let t): return "text \"\(t)\""
    case .composition(let t): return "composing \"\(t)\""
    case .frame(_): return ""
    case .themeChanged(let t): return t == .dark ? "dark" : "light"
    }
}

func main() async -> int32 {
    let w: window.Window
    do {
        w = try window.Create(title: "Hello", size: window.Size(640, 400))
    } catch let e as window.WindowError {
        print("failed: \(e.Message)")
        return 1
    } catch {
        return 1
    }
    print("\(w.Size().Width)x\(w.Size().Height) points, \(w.PixelSize().Width)x\(w.PixelSize().Height) pixels")
    while let event = await w.WaitEvent() {
        let line = describe(event)
        if !line.isEmpty {
            print(line)
        }
        switch event {
        case .closeRequested:
            w.Close()
            return 0
        case .keyDown(let k):
            if k.Code == .escape {
                w.Close()
                return 0
            }
        default:
            break
        }
    }
    return 0
}
