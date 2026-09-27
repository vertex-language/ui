// A small desktop browser: a ui/webview under an address bar with back
// and forward. Everything about pages -- loading them from files or the
// network, history, following links -- is the webview's; this program
// draws its chrome and hands the window's events on. A page from the
// network prints a report of what the engine couldn't use.
//
//     vsc run browser [page.html | https://...]
//     vsc run browser -- --snapshot out.png https://github.com
//     vsc run browser -- --record site/ https://github.com   (see web/cmd/snapshot --archive)
package main

import (
    "fs"
    "image"
    "image/png"
    "image/draw"
    "text/font"
    "ui/webview"
    "ui/window"
)

let chromeHeight: float32 = 44

/// The page the browser starts on: the web engine's sample pages, from
/// the web repository or beside it.
func startPage() -> string {
    var dir = ""
    if let cwd = try? fs.Canonical(fs.Path(".")) {
        let s = cwd.String()
        dir = s.hasSuffix("/") ? s : s + "/"
    }
    for candidate in ["testdata/pages/home.html", "../web/testdata/pages/home.html"] {
        if (try? fs.Stat(fs.Path(dir + candidate))) != nil { return dir + candidate }
    }
    return dir + "testdata/pages/home.html"
}

@MainActor
final class Browser {
    let win: window.Window
    let surface: window.Surface
    let view: webview.WebView
    var pixels: [uint8] = []
    var pixelSize: window.PixelSize
    var status: string = ""
    var cursor: window.Cursor = window.Cursor.arrow
    var frameWanted = false
    /// A file the first frame of a finished page is written to as a PNG,
    /// and the program ends: --snapshot path.
    var snapshotPath: string? = nil
    var done = false

    init(win: window.Window) {
        self.win = win
        surface = win.Surface()
        view = webview.WebView()
        view.StartPage = startPage()
        pixelSize = win.PixelSize()
        pixels = [uint8](repeating: 0, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
        let size = win.Size()
        view.SetBounds(origin: window.Point(0, chromeHeight), size: window.Size(size.Width, size.Height - chromeHeight))
    }

    func requestFrame() {
        if !frameWanted {
            frameWanted = true
            win.RequestFrame()
        }
    }

    func resized() {
        let newPx = win.PixelSize()
        if newPx.Width != pixelSize.Width || newPx.Height != pixelSize.Height {
            pixelSize = newPx
            pixels = [uint8](repeating: 0, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
        }
        let size = win.Size()
        view.SetBounds(origin: window.Point(0, chromeHeight), size: window.Size(size.Width, size.Height - chromeHeight))
        requestFrame()
    }

    /// The address bar, the buttons, and the status text.
    func drawChrome(_ canvas: draw.Canvas, scale: float32) {
        let w = canvas.Width
        let h = int32(chromeHeight * scale)
        canvas.Fill(draw.IRect(0, 0, w, h), draw.Color(0xf0, 0xf2, 0xf5))
        canvas.Fill(draw.IRect(0, h - 1, w, 1), draw.Color(0xd0, 0xd7, 0xde))
        let face = font.Load(font.Spec(family: "system-ui", size: 13))
        let on = draw.Color(0x24, 0x29, 0x2f)
        let off = draw.Color(0xb0, 0xb4, 0xba)
        font.DrawRun(canvas, face.Shape("◀"), x: 14 * scale, baseline: 27 * scale, scale: scale, color: view.CanGoBack ? on : off)
        font.DrawRun(canvas, face.Shape("▶"), x: 40 * scale, baseline: 27 * scale, scale: scale, color: view.CanGoForward ? on : off)
        let bar = draw.Rect(70, 8, float32(w) / scale - 84, chromeHeight - 16).Snapped(scale: scale)
        canvas.FillRounded(bar, radii: draw.Radii(all: 6 * scale), draw.Color.white)
        let gray = draw.Color(0xd0, 0xd7, 0xde)
        canvas.FillRing(bar, radii: draw.Radii(all: 6 * scale), widths: draw.Edges(all: scale), colors: [gray, gray, gray, gray])
        var clipped = canvas
        clipped.ClipTo(bar)
        font.DrawRun(clipped, face.Shape(status.isEmpty ? view.URL : status), x: 82 * scale, baseline: 27 * scale, scale: scale,
                     color: status.isEmpty ? on : draw.Color(0x57, 0x60, 0x6a))
    }

    func frame(_ time: float64) {
        frameWanted = false
        if view.Advance(time: time) || view.NeedsAnimation() {
            // A blinking caret wants the next frame too.
            requestFrame()
        }
        let scale = win.ScaleFactor()
        draw.WithCanvas(&pixels, width: pixelSize.Width, height: pixelSize.Height) { c in
            drawChrome(c, scale: scale)
        }
        view.Draw(into: &pixels, canvasSize: pixelSize, scale: scale)
        do {
            try surface.Present(pixels, size: pixelSize)
        } catch let e as window.WindowError {
            print("present: \(e.Message)")
        } catch {}
        if let path = snapshotPath, !done, !view.IsLoading {
            try? fs.WriteFile(fs.Path(path), png.Encode(image.RGBA(width: int(pixelSize.Width), height: int(pixelSize.Height), pixels: pixels)))
            done = true
            // One more event, for the loop to see that it's done.
            win.RequestFrame()
        }
    }

    func handle(_ event: window.Event) -> bool {
        switch event {
        case .closeRequested:
            return false
        case .resized(_), .scaleFactorChanged(_):
            resized()
            return true
        case .keyDown(let k):
            if k.Modifiers.Meta && (k.Code == .bracketLeft || k.Code == .bracketRight || k.Code == .r) {
                if k.Code == .bracketLeft { view.Back() } else if k.Code == .bracketRight { view.Forward() } else { view.Reload() }
                requestFrame()
                return true
            }
            if k.Code == .escape && view.Page.FocusedElement == nil { return false }
        case .pointerDown(let p, _):
            if p.Position.Y < chromeHeight {
                if p.Position.X < 32 { view.Back() } else if p.Position.X < 60 { view.Forward() }
                requestFrame()
                return true
            }
        case .frame(let f):
            frame(f.Time)
            return true
        default:
            break
        }
        _ = view.Handle(event)
        let c = view.DesiredCursor()
        if c != cursor {
            cursor = c
            win.SetCursor(c)
        }
        if view.NeedsRepaint() || view.NeedsAnimation() { requestFrame() }
        return true
    }
}

func main() async -> int32 {
    var options = window.Options()
    options.MinSize = window.Size(480, 320)
    let win: window.Window
    do {
        win = try window.Create(title: "Vertex Browser", size: window.Size(1000, 760), options: options)
    } catch let e as window.WindowError {
        print("failed to create window: \(e.Message)")
        return 1
    } catch {
        return 1
    }

    let browser = Browser(win: win)
    let view = browser.view
    view.OnLoadStarted { address in
        browser.status = "Loading \(address)…"
        browser.requestFrame()
    }
    view.OnLoadFinished { report in
        if report.Resources > 0 || report.Status != 200 { print(report.Text()) }
        browser.status = ""
        browser.requestFrame()
    }
    view.Page.OnHoverLink { link in
        browser.status = link ?? ""
        browser.requestFrame()
    }
    view.Page.OnSubmit { submission in
        var text = "Submitted to \(submission.Action) by \(submission.Method):"
        for f in submission.Fields {
            text += " \(f.Name)=\(f.Value)"
        }
        print(text)
        browser.status = text
        browser.requestFrame()
    }
    view.Page.OnTitleChanged { title in
        win.SetTitle(title.isEmpty ? "Vertex Browser" : title + " — Vertex Browser")
    }

    var args = CommandLine.arguments
    while args.count > 2 && (args[1] == "--snapshot" || args[1] == "--record") {
        if args[1] == "--snapshot" { browser.snapshotPath = args[2] } else { view.RecordInto = args[2] }
        args.remove(at: 1)
        args.remove(at: 1)
    }
    view.Navigate(args.count > 1 ? args[1] : "about:home")

    while let event = await win.WaitEvent() {
        if !browser.handle(event) || browser.done {
            win.Close()
            return 0
        }
    }
    return 0
}
