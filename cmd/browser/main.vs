// A small desktop browser over ui/webview: an address bar, back and
// forward, and pages from files or the network. A page from the network
// is fetched with what it refers to before it is shown, and a report of
// what the engine couldn't use is printed (net.vs).
//
//     vsc run browser [page.html | https://...]
//     vsc run browser -- --snapshot out.png https://github.com
package main

import (
    "fs"
    "image"
    "image/png"
    "image/draw"
    "text/font"
    "ui/webview"
    "ui/window"
    "web/fetch"
)

let chromeHeight: float32 = 44

/// The page the browser starts on, when it is given none: the web
/// engine's sample pages, from the web repository or beside it.
func startPage(_ dir: string) -> string {
    for candidate in ["testdata/pages/home.html", "../web/testdata/pages/home.html"] {
        if (try? fs.Stat(fs.Path(dir + candidate))) != nil { return dir + candidate }
    }
    return dir + "testdata/pages/home.html"
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
    var visited: Set<string> = []
    var url: string = ""
    var status: string = ""
    var cursor: window.Cursor = window.Cursor.arrow
    var frameWanted = false
    /// A file the first frame is written to as a PNG, for looking at the
    /// browser without a screen: --snapshot path.
    var snapshotPath: string? = nil
    var snapshotTaken = false
    /// Counts loads, so that a page fetched after the user went elsewhere
    /// is dropped.
    var loads = 0
    var loading = false
    /// Set once a snapshot is written: the program ends.
    var done = false

    init(win: window.Window) {
        self.win = win
        surface = win.Surface()
        view = webview.WebView()
        pixelSize = win.PixelSize()
        pixels = [uint8](repeating: 0, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
        let size = win.Size()
        view.SetBounds(origin: window.Point(0, chromeHeight), size: window.Size(size.Width, size.Height - chromeHeight))
        view.Page.IsVisited { url in self.visited.contains(url) }
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
        visited.insert(target)
        loads += 1
        let scheme = fetch.Scheme(target)
        if scheme == "http" || scheme == "https" {
            let generation = loads
            loading = true
            status = "Loading \(target)…"
            Task { await self.loadRemote(target, generation) }
        } else if target == "about:home" || target.isEmpty {
            loading = false
            view.Page.Configuration.Fetcher = fetch.Fetcher()
            load(startPage(workingDirectory()))
        } else if scheme == "" || scheme == "file" {
            loading = false
            view.Page.Configuration.Fetcher = fetch.Fetcher()
            load(fetch.FilePath(target))
        } else {
            loading = false
            showMessage("Can't open this", "There's no way to open <code>\(target)</code> here.")
        }
        if record {
            while history.count > position + 1 { history.removeLast() }
            history.append(url)
            position = history.count - 1
        }
        win.SetTitle(view.Page.Title.isEmpty ? "Vertex Browser" : view.Page.Title + " — Vertex Browser")
        requestFrame()
    }

    /// Fetches a page and what it refers to, then shows it.
    func loadRemote(_ target: string, _ generation: int) async {
        let remote = await fetchPage(target)
        if generation != loads { return }
        loading = false
        status = ""
        print(report(remote))
        guard remote.page.ok, let body = remote.page.body else {
            let why = remote.page.status == 0 ? remote.page.error : "the server answered \(remote.page.status)"
            showMessage("Can't load the page", "<code>\(target)</code>: \(why)")
            requestFrame()
            return
        }
        url = remote.url
        if history.count > 0 && position >= 0 && position < history.count { history[position] = remote.url }
        let resources = remote.resources
        view.Page.Configuration.Fetcher = fetch.Fetcher({ u in
            if let l = resources[u], l.ok { return l.body }
            return nil
        })
        view.Page.LoadHTML(string(decoding: body, as: UTF8.self), baseURL: remote.url)
        win.SetTitle(view.Page.Title.isEmpty ? "Vertex Browser" : view.Page.Title + " — Vertex Browser")
        requestFrame()
    }

    func showMessage(_ heading: string, _ text: string) {
        view.Page.LoadHTML("<body style='font-family:system-ui;margin:40px;color:#333'><h2 style='margin-top:0'>\(heading)</h2><p>\(text)</p><p><a href='about:home'>Start page</a></p></body>")
    }

    func load(_ path: string) {
        do {
            try view.Page.LoadFile(path)
        } catch {
            view.Page.LoadHTML("<body style='font-family:system-ui;margin:40px'><h2>Cannot open the file</h2><p>\(path)</p><p><a href='about:home'>Start page</a></p></body>")
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
        if let path = snapshotPath, !snapshotTaken, !loading {
            snapshotTaken = true
            try? fs.WriteFile(fs.Path(path), png.Encode(image.RGBA(width: int(pixelSize.Width), height: int(pixelSize.Height), pixels: pixels)))
            done = true
            // One more event, for the loop to see that it's done.
            win.RequestFrame()
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
            if k.Code == .escape && view.Page.FocusedElement == nil {
                return false
            }
            if k.Modifiers.Meta && k.Code == .bracketLeft { back(); return true }
            if k.Modifiers.Meta && k.Code == .bracketRight { forward(); return true }
            if k.Modifiers.Meta && k.Code == .r { go(url, record: false); return true }
            if view.Handle(event) == .handled || view.NeedsRepaint() || view.NeedsAnimation() { requestFrame() }
        case .text(_):
            if view.Handle(event) == .handled { requestFrame() }
        case .pointerMoved(_):
            _ = view.Handle(event)
            let c = view.DesiredCursor()
            if c != cursor {
                cursor = c
                win.SetCursor(c)
            }
            if view.NeedsRepaint() { requestFrame() }
        case .pointerDown(let p, _):
            if chromeClick(p.Position) { return true }
            _ = view.Handle(event)
            if view.NeedsRepaint() || view.NeedsAnimation() { requestFrame() }
        case .pointerUp(_, _):
            _ = view.Handle(event)
            if view.NeedsRepaint() { requestFrame() }
        case .scrolled(_), .pointerLeft:
            _ = view.Handle(event)
            if view.NeedsRepaint() { requestFrame() }
        case .frame(let f):
            frame(f.Time)
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
    view.Page.OnNavigate { target in
        browser.go(target)
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
    view.Page.OnAction { name, value in
        print("action \(name): \(value)")
    }
    view.Page.OnTitleChanged { title in
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
        if !browser.handle(event) || browser.done {
            win.Close()
            return 0
        }
    }
    return 0
}
