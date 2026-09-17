// Paint with the pointer. Pixels are drawn on the CPU and shown with
// Surface.Present, once per display frame while something has changed.
// C clears the canvas; Escape or closing the window quits.
package main

import window

struct Canvas {
    var size: window.PixelSize
    var pixels: [uint8]
    var dark: bool
}

func clear(_ c: inout Canvas) {
    let shade: uint8 = c.dark ? 28 : 238
    var i = 0
    while i < c.pixels.count {
        c.pixels[i] = shade
        c.pixels[i + 1] = shade
        c.pixels[i + 2] = shade
        c.pixels[i + 3] = 255
        i += 4
    }
}

func resized(_ c: inout Canvas, _ size: window.PixelSize) {
    c.size = size
    c.pixels = [uint8](repeating: 0, count: int(size.Width) * int(size.Height) * 4)
    clear(&c)
}

// dot paints a filled circle, in pixels, centred on (x, y).
func dot(_ c: inout Canvas, _ x: int32, _ y: int32, _ radius: int32) {
    var dy = -radius
    while dy <= radius {
        var dx = -radius
        while dx <= radius {
            let px = x + dx
            let py = y + dy
            if dx * dx + dy * dy <= radius * radius && px >= 0 && py >= 0 &&
                px < c.size.Width && py < c.size.Height {
                let at = (int(py) * int(c.size.Width) + int(px)) * 4
                c.pixels[at] = 40
                c.pixels[at + 1] = 120
                c.pixels[at + 2] = 230
                c.pixels[at + 3] = 255
            }
            dx += 1
        }
        dy += 1
    }
}

func main() async -> int32 {
    var options = window.Options()
    options.MinSize = window.Size(200, 150)
    let w: window.Window
    do {
        w = try window.Create(title: "Paint", size: window.Size(800, 600), options: options)
    } catch let e as window.WindowError {
        print("failed: \(e.Message)")
        return 1
    } catch {
        return 1
    }
    var canvas = Canvas(size: w.PixelSize(), pixels: [], dark: w.Theme() == .dark)
    resized(&canvas, w.PixelSize())
    let surface = w.Surface()
    var down = false
    var waiting = false

    // Ask for a frame when there is something new to show, and only then:
    // an idle window draws nothing.
    func changed() {
        if !waiting {
            w.RequestFrame()
            waiting = true
        }
    }
    changed()

    while let event = await w.WaitEvent() {
        switch event {
        case .closeRequested:
            w.Close()
            return 0
        case .keyDown(let k):
            if k.Code == .escape {
                w.Close()
                return 0
            }
            if k.Code == .c {
                clear(&canvas)
                changed()
            }
        case .resized(_), .scaleFactorChanged(_):
            resized(&canvas, w.PixelSize())
            changed()
        case .themeChanged(let t):
            canvas.dark = t == .dark
            clear(&canvas)
            changed()
        case .pointerDown(let p, let button):
            if button == .primary {
                down = true
                let scale = w.ScaleFactor()
                dot(&canvas, int32(p.Position.X * scale), int32(p.Position.Y * scale), int32(6 * scale))
                changed()
            }
        case .pointerUp(_, _):
            down = false
        case .pointerMoved(let p):
            if down {
                let scale = w.ScaleFactor()
                dot(&canvas, int32(p.Position.X * scale), int32(p.Position.Y * scale), int32(6 * scale))
                changed()
            }
        case .frame(_):
            waiting = false
            do {
                try surface.Present(canvas.pixels, size: canvas.size)
            } catch let e as window.WindowError {
                print("present: \(e.Message)")
            } catch {
            }
        default:
            break
        }
    }
    return 0
}
