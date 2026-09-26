// Times the engine on a page: the first render, a relayout, a repaint,
// and the pointer moving across the page.
//
//     vsc run bench -- page.html [width] [height]
package main

import "time"
import "ui/window"
import "ui/draw"
import "ui/webview"

func number(_ s: string, _ fallback: float32) -> float32 {
    let b = [uint8](s.utf8)
    if b.isEmpty { return fallback }
    let v = draw.parseNumber(b, 0, b.count)
    return v > 0 ? v : fallback
}

func ms(_ d: time.Duration) -> string {
    let us = d.AsMicroseconds()
    return "\(us / 1000).\((us % 1000) / 100) ms"
}

@MainActor
func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 2 {
        print("usage: bench page.html [width] [height]")
        return 2
    }
    let width = number(args.count > 2 ? args[2] : "", 900)
    let height = number(args.count > 3 ? args[3] : "", 700)
    let scale: float32 = 2
    let pw = int32(width * scale)
    let ph = int32(height * scale)
    var pixels = [uint8](repeating: 0, count: int(pw) * int(ph) * 4)
    let size = window.PixelSize(pw, ph)

    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(width, height))
    var t = time.Instant.Now()
    do {
        try view.LoadFile(args[1])
    } catch {
        print("cannot read \(args[1])")
        return 1
    }
    print("load (parse + sheets): \(ms(t.Elapsed()))")

    t = time.Instant.Now()
    view.Draw(into: &pixels, canvasSize: size, scale: scale)
    print("first frame (style, layout, paint, raster): \(ms(t.Elapsed()))")

    view.SetBounds(origin: window.Point(0, 0), size: window.Size(width - 1, height))
    t = time.Instant.Now()
    view.Draw(into: &pixels, canvasSize: size, scale: scale)
    print("resize (layout, paint, raster): \(ms(t.Elapsed()))")

    view.SetScrollOffset(window.Point(0, 100))
    t = time.Instant.Now()
    view.Draw(into: &pixels, canvasSize: size, scale: scale)
    print("scroll (raster): \(ms(t.Elapsed()))")

    view.Invalidate()
    t = time.Instant.Now()
    view.Draw(into: &pixels, canvasSize: size, scale: scale)
    print("invalidate (style, layout, paint, raster): \(ms(t.Elapsed()))")

    // The pointer sweeps the page in a grid; each stop may restyle.
    var restyles = 0
    var frames = 0
    t = time.Instant.Now()
    var y: float32 = 5
    while y < height {
        var x: float32 = 5
        while x < width {
            _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(x, y))))
            if view.NeedsRepaint() {
                frames += 1
                view.Draw(into: &pixels, canvasSize: size, scale: scale)
            }
            x += 25
        }
        y += 25
    }
    _ = restyles
    let sweep = t.Elapsed()
    let stops = int(width / 25) * int(height / 25)
    print("pointer sweep: \(stops) stops, \(frames) frames, \(ms(sweep)) total, \(sweep.AsMicroseconds() / int64(stops)) us per stop")
    return 0
}
