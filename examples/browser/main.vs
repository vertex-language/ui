// A small desktop browser over ui/webview: an address bar, back and
// forward, and pages loaded from files. Links between local pages are
// followed; anything else is shown as a page that says where it went.
//
//     vsc run browser [page.html]
package main

import "fs"
import "ui/window"
import "ui/draw"
import "ui/font"
import "ui/webview"

let chromeHeight: float32 = 44

/// The page the browser starts on, when it is given none.
func startPage(_ dir: string) -> string {
    return dir + "examples/pages/home.html"
}

/// The folder the program was started in, for finding the sample pages.
func workingDirectory() -> string {
    if let cwd = try? fs.Canonical(fs.Path(".")) {
        let s = cwd.String()
        return s.hasSuffix("/") ? s : s + "/"
    }
    return ""
}

@MainActor
final class Browser {
    let win: window.Window
    let surface: window.Surface
    let view: webview.WebView
    var pixels: [uint8] = []
    var pixelSize: window.PixelSize
    var history: [string] = []
    var position: int = -1
    var url: string = ""
    var status: string = ""
    var cursor: window.Cursor = window.Cursor.arrow
    var frameWanted = false
    /// A file the first frame is written to as a PNG, for looking at the
    /// browser without a screen: --snapshot path.
    var snapshotPath: string? = nil
    var snapshotTaken = false

    init(win: window.Window) {
        self.win = win
        surface = win.Surface()
        view = webview.WebView()
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

    /// Loads a page by URL or path and records it in the history.
    func go(_ target: string, record: Bool = true) {
        url = target
        if target.contains("://") {
            view.LoadHTML("""
            <body style="font-family: system-ui; margin: 40px; color: #333">
              <h2 style="margin-top:0">This browser stays on disk</h2>
              <p>It was asked to open <code style="background:#eee;padding:2px 6px;border-radius:4px">\(target)</code>.</p>
              <p>Fetching pages over the network is the host's job; the webview renders whatever it is handed.</p>
              <p><a href="about:home">Back to the start page</a></p>
            </body>
            """)
        } else if target == "about:home" || target.isEmpty {
            load(startPage(workingDirectory()))
        } else {
            load(target)
        }
        if record {
            while history.count > position + 1 { history.removeLast() }
            history.append(url)
            position = history.count - 1
        }
        win.SetTitle(view.Title.isEmpty ? "Vertex Browser" : view.Title + " — Vertex Browser")
        requestFrame()
    }

    func load(_ path: string) {
        do {
            try view.LoadFile(path)
        } catch {
            view.LoadHTML("<body style='font-family:system-ui;margin:40px'><h2>Cannot open the file</h2><p>\(path)</p><p><a href='about:home'>Start page</a></p></body>")
        }
    }

    func back() {
        if position > 0 {
            position -= 1
            go(history[position], record: false)
        }
    }

    func forward() {
        if position + 1 < history.count {
            position += 1
            go(history[position], record: false)
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
        // Back and forward.
        let enabledBack = position > 0
        let enabledForward = position + 1 < history.count
        font.DrawRun(canvas, face.Shape("◀"), x: 14 * scale, baseline: 27 * scale, scale: scale,
                     color: enabledBack ? draw.Color(0x24, 0x29, 0x2f) : draw.Color(0xb0, 0xb4, 0xba))
        font.DrawRun(canvas, face.Shape("▶"), x: 40 * scale, baseline: 27 * scale, scale: scale,
                     color: enabledForward ? draw.Color(0x24, 0x29, 0x2f) : draw.Color(0xb0, 0xb4, 0xba))
        // The address.
        let bar = draw.Rect(70, 8, float32(w) / scale - 84, chromeHeight - 16).Snapped(scale: scale)
        canvas.FillRounded(bar, radii: draw.Radii(all: 6 * scale), draw.Color.white)
        let gray = draw.Color(0xd0, 0xd7, 0xde)
        canvas.FillRing(bar, radii: draw.Radii(all: 6 * scale), widths: draw.Edges(all: scale), colors: [gray, gray, gray, gray])
        var shown = url
        if !status.isEmpty { shown = status }
        var clipped = canvas
        clipped.ClipTo(bar)
        font.DrawRun(clipped, face.Shape(shown), x: 82 * scale, baseline: 27 * scale, scale: scale,
                     color: status.isEmpty ? draw.Color(0x24, 0x29, 0x2f) : draw.Color(0x57, 0x60, 0x6a))
    }

    func frame() {
        frameWanted = false
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
        if let path = snapshotPath, !snapshotTaken {
            snapshotTaken = true
            try? fs.WriteFile(fs.Path(path), draw.EncodePNG(draw.Image(width: pixelSize.Width, height: pixelSize.Height, pixels: pixels)))
        }
    }

    func chromeClick(_ p: window.Point) -> bool {
        if p.Y >= chromeHeight { return false }
        if p.X < 32 { back() } else if p.X < 60 { forward() }
        return true
    }

    func handle(_ event: window.Event) -> bool {
        switch event {
        case .closeRequested:
            return false
        case .resized(_), .scaleFactorChanged(_):
            resized()
        case .keyDown(let k):
            if k.Code == .escape && view.FocusedElement == nil {
                return false
            }
            if k.Modifiers.Meta && k.Code == .bracketLeft { back(); return true }
            if k.Modifiers.Meta && k.Code == .bracketRight { forward(); return true }
            if k.Modifiers.Meta && k.Code == .r { go(url, record: false); return true }
            if view.Handle(event) == .handled || view.NeedsRepaint() { requestFrame() }
        case .text(_):
            if view.Handle(event) == .handled { requestFrame() }
        case .pointerMoved(_):
            _ = view.Handle(event)
            if let c = view.DesiredCursor(), c != cursor {
                cursor = c
                win.SetCursor(c)
            }
            if view.NeedsRepaint() { requestFrame() }
        case .pointerDown(let p, _):
            if chromeClick(p.Position) { return true }
            _ = view.Handle(event)
            if view.NeedsRepaint() { requestFrame() }
        case .pointerUp(_, _):
            _ = view.Handle(event)
            if view.NeedsRepaint() { requestFrame() }
        case .scrolled(_), .pointerLeft:
            _ = view.Handle(event)
            if view.NeedsRepaint() { requestFrame() }
        case .frame(_):
            frame()
        default:
            break
        }
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
    view.OnNavigate { target in
        browser.go(target)
    }
    view.OnHoverLink { link in
        browser.status = link ?? ""
        browser.requestFrame()
    }
    view.OnSubmit { submission in
        var text = "Submitted to \(submission.Action) by \(submission.Method):"
        for f in submission.Fields {
            text += " \(f.Name)=\(f.Value)"
        }
        print(text)
        browser.status = text
        browser.requestFrame()
    }
    view.OnAction { name, value in
        print("action \(name): \(value)")
    }
    view.OnTitleChanged { title in
        win.SetTitle(title.isEmpty ? "Vertex Browser" : title + " — Vertex Browser")
    }

    var args = CommandLine.arguments
    if args.count > 2 && args[1] == "--snapshot" {
        browser.snapshotPath = args[2]
        args.remove(at: 1)
        args.remove(at: 1)
    }
    browser.go(args.count > 1 ? args[1] : "about:home")

    while let event = await win.WaitEvent() {
        if !browser.handle(event) {
            win.Close()
            return 0
        }
    }
    return 0
}
