// A window filled with one colour, redrawn whenever it is asked to be.
// The smallest thing that shows a window works on a platform: on Android,
// built with --emit lib and packaged with androidpkg, it is the app.
package main

import "ui/window"

func main() async -> int32 {
    let w: window.Window
    do {
        w = try window.Create(title: "Blank", size: window.Size(640, 400))
    } catch let e as window.WindowError {
        print("failed: \(e.Message)")
        return 1
    } catch {
        return 1
    }
    let surface = w.Surface()
    print("\(w.Size().Width)x\(w.Size().Height) points, \(w.PixelSize().Width)x\(w.PixelSize().Height) pixels, scale \(w.ScaleFactor())")
    while let event = await w.WaitEvent() {
        switch event {
        case .closeRequested:
            print("close requested")
            w.Close()
            return 0
        case .keyDown(let k):
            if k.Code == .escape {
                w.Close()
                return 0
            }
        case .pointerDown(let p, _):
            print("pointer down at \(p.Position.X),\(p.Position.Y)")
        case .frame(_):
            let size = w.PixelSize()
            if size.Width > 0 && size.Height > 0 {
                var pixels = [uint8](repeating: 255, count: int(size.Width) * int(size.Height) * 4)
                var i = 0
                while i < pixels.count {
                    pixels[i] = 38
                    pixels[i + 1] = 99
                    pixels[i + 2] = 235
                    i += 4
                }
                try? surface.Present(pixels, size: size)
            }
        default:
            break
        }
    }
    return 0
}
