// Package app runs a .vsx program as a desktop app: a window, a page in
// it drawn by the engine, and a root of markup mounted into the page.
//
//     func main() async -> int32 {
//         return await app.Run(title: "Counter", css: styles) { <Counter start={5} /> }
//     }
//
// A click, a key or typing reaches the page's elements as events; the
// handlers they run write state; and the root is rendered again and the
// page patched once the event is done (proposed_vsx.md §8.1). This is the
// first form of app.Run: one window, and styles given as a string until
// .vss files are compiled. `--snapshot out.png` on the command line draws
// the first frame into a PNG and quits; `--dark` and `--light` show the app
// in that appearance, whatever the system's.
package app

import (
    "fs"
    "image"
    "image/png"
    "ui/state"
    "ui/component"
    "ui/webview"
    "ui/window"
    "web"
)

/// The window, its page, and the root mounted in it.
@MainActor
final class Host {
    let win: window.Window
    let surface: window.Surface
    let view: webview.WebView
    var pixels: [uint8] = []
    var pixelSize: window.PixelSize
    var cursor: window.Cursor = window.Cursor.arrow
    var frameWanted = false
    var mounted: component.Mounted? = nil
    var snapshotPath: string? = nil
    var done = false
    /// The appearance --dark or --light asked for, which the system's
    /// does not change.
    var forced: bool? = nil

    init(win: window.Window) {
        self.win = win
        surface = win.Surface()
        view = webview.WebView()
        pixelSize = win.PixelSize()
        pixels = [uint8](repeating: 0, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
        view.SetBounds(origin: window.Point(0, 0), size: win.Size())
        // An app's page goes nowhere: a link or a submit is the app's to
        // handle, in its handlers.
        view.Page.OnNavigate { _ in }
        view.Page.OnSubmit { _ in }
    }

    func mount(css: string, _ root: () -> component.Node) {
        view.Page.LoadHTML("<!doctype html><html><head><style>" + baseCSS + css + "</style></head><body></body></html>")
        let doc = view.Page.Document!
        let body = doc.Tree.ElementsByTagName("body").first!
        let page = view.Page
        mounted = component.Mount(root, into: doc, at: body, styles: { sheets in page.SetStyleSheets(sheets) })
    }

    func requestFrame() {
        if !frameWanted {
            frameWanted = true
            win.RequestFrame()
        }
    }

    func resized() {
        let px = win.PixelSize()
        if px.Width != pixelSize.Width || px.Height != pixelSize.Height {
            pixelSize = px
            pixels = [uint8](repeating: 0, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
        }
        view.SetBounds(origin: window.Point(0, 0), size: win.Size())
        requestFrame()
    }

    func frame(_ time: float64) {
        frameWanted = false
        if view.Advance(time: time) || view.NeedsAnimation() { requestFrame() }
        view.Draw(into: &pixels, canvasSize: pixelSize, scale: win.ScaleFactor())
        do {
            try surface.Present(pixels, size: pixelSize)
        } catch let e as window.WindowError {
            print("present: \(e.Message)")
        } catch {}
        if let path = snapshotPath, !done {
            try? fs.WriteFile(fs.Path(path), png.Encode(image.RGBA(width: int(pixelSize.Width), height: int(pixelSize.Height), pixels: pixels)))
            done = true
            win.RequestFrame()
        }
    }

    /// Takes a window event; false when the app should end.
    func handle(_ event: window.Event) -> bool {
        switch event {
        case .closeRequested:
            return false
        case .resized(_), .scaleFactorChanged(_):
            resized()
            return true
        case .frame(let f):
            frame(f.Time)
            return true
        case .themeChanged(let t):
            // The system's appearance: what prefers-color-scheme answers.
            if forced == nil { view.Page.SetColorScheme(dark: t == .dark) }
            requestFrame()
            return true
        default:
            break
        }
        // The event's handlers write state; the root renders again once,
        // after them.
        state.Batch { _ = self.view.Handle(event) }
        let c = view.DesiredCursor()
        if c != cursor {
            cursor = c
            win.SetCursor(c)
        }
        if view.NeedsRepaint() || view.NeedsAnimation() { requestFrame() }
        return true
    }
}

/// The page's own styles, under the app's: the system font, and no margin
/// around the body.
let baseCSS = "html { font: 14px system-ui; } body { margin: 0; }\n"

/// Opens a window titled title, mounts root in it, and runs until the
/// window is closed. Answers the program's exit status.
@MainActor
public func Run(title: string, width: float32 = 800, height: float32 = 600, css: string = "", _ root: () -> component.Node) async -> int32 {
    var options = window.Options()
    options.MinSize = window.Size(240, 160)
    let win: window.Window
    do {
        win = try window.Create(title: title, size: window.Size(width, height), options: options)
    } catch let e as window.WindowError {
        print("app: \(e.Message)")
        return 1
    } catch {
        return 1
    }
    let host = Host(win: win)
    // --snapshot out.png draws a frame and quits; --dark and --light
    // show the app in that appearance, whatever the system's.
    var forced: bool? = nil
    var args = CommandLine.arguments
    var i = 1
    while i < args.count {
        if args[i] == "--snapshot" && i + 1 < args.count {
            host.snapshotPath = args[i + 1]
            i += 1
        } else if args[i] == "--dark" {
            forced = true
        } else if args[i] == "--light" {
            forced = false
        }
        i += 1
    }
    host.forced = forced
    host.view.Page.SetColorScheme(dark: forced ?? (win.Theme() == .dark))
    host.mount(css: css, root)
    host.requestFrame()
    while let event = await win.WaitEvent() {
        if !host.handle(event) || host.done {
            host.mounted?.Unmount()
            win.Close()
            return 0
        }
    }
    return 0
}
