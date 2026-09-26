// Renders an HTML file to a PNG without a window: for looking at what
// the engine draws, and for comparing renders.
//
//     vsc run snapshot -- page.html out.png [width] [height] [scale]
package main

import "fs"
import "ui/window"
import "ui/draw"
import "ui/webview"
import "image"
import "image/png"

func number(_ s: string, _ fallback: float32) -> float32 {
    let b = [uint8](s.utf8)
    if b.isEmpty { return fallback }
    let v = draw.parseNumber(b, 0, b.count)
    return v > 0 ? v : fallback
}

func main() -> int32 {
    let args = CommandLine.arguments
    if args.count < 3 {
        print("usage: snapshot page.html out.png [width] [height] [scale]")
        return 2
    }
    let width = number(args.count > 3 ? args[3] : "", 800)
    let height = number(args.count > 4 ? args[4] : "", 600)
    let scale = number(args.count > 5 ? args[5] : "", 1)

    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(width, height))
    do {
        try view.LoadFile(args[1])
    } catch {
        print("cannot read \(args[1])")
        return 1
    }
    let pw = int32(width * scale)
    let ph = int32(height * scale)
    var pixels = [uint8](repeating: 0, count: int(pw) * int(ph) * 4)
    view.Draw(into: &pixels, canvasSize: window.PixelSize(pw, ph), scale: scale)
    let encoded = png.Encode(image.RGBA(width: int(pw), height: int(ph), pixels: pixels))
    do {
        try fs.WriteFile(fs.Path(args[2]), encoded)
    } catch {
        print("cannot write \(args[2])")
        return 1
    }
    let content = view.ContentSize()
    print("rendered \(args[1]): \(pw)x\(ph) pixels, content \(content.Width)x\(content.Height) points")
    return 0
}
