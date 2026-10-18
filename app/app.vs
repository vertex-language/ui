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
// the first frame into a PNG and quits (`--snapshot-after 2`: the first
// frame two seconds in); `--dark` and `--light` show the app
// in that appearance, whatever the system's.
package app

import (
    "fs"
    "image"
    "image/png"
    "os/env"
    "time"
    "ui/state"
    "ui/component"
    "ui/viewport"
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
    /// The pixels don't hold the page: it hasn't been painted at this size.
    var stale = true
    var mounted: component.Mounted? = nil
    var snapshotPath: string? = nil
    /// --snapshot-after seconds: the snapshot is the first frame after
    /// this long, for an app whose content arrives (a shell's prompt).
    var snapshotAfter: float64 = 0
    let snapshotBegun = time.Instant.Now()
    var done = false
    /// The appearance --dark or --light asked for, which the system's
    /// does not change.
    var forced: bool? = nil
    /// VSX_TRACE=1 in the environment: print what each frame and each
    /// slow event cost.
    let trace = (env.Get("VSX_TRACE") ?? "") != ""

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
        mounted = component.Mount(root, into: doc, at: body, styles: { sheets in page.SetStyleSheets(sheets) }, focus: { n in page.Focus(n) }, measure: { n in page.BoundsOf(n) })
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
        stale = true
        view.SetBounds(origin: window.Point(0, 0), size: win.Size())
        requestFrame()
    }

    func frame(_ t: float64) {
        frameWanted = false
        let t0 = time.Instant.Now()
        if view.Advance(time: t) || view.NeedsAnimation() { requestFrame() }
        // The page is painted only when it changed; the pixels keep it
        // between, and viewports draw over their boxes alone.
        let repaint = view.NeedsRepaint() || stale
        if repaint {
            view.Draw(into: &pixels, canvasSize: pixelSize, scale: win.ScaleFactor())
            stale = false
        }
        let t1 = time.Instant.Now()
        let drew = viewport.Composite(view.Page, &pixels, width: int(pixelSize.Width), height: int(pixelSize.Height),
                                      scale: win.ScaleFactor(), time: t, all: repaint)
        let t2 = time.Instant.Now()
        if viewport.Wanted() { requestFrame() }
        if repaint || drew || snapshotPath != nil {
            do {
                try surface.Present(pixels, size: pixelSize)
            } catch let e as window.WindowError {
                print("present: \(e.Message)")
            } catch {}
        }
        if trace && (repaint || drew) {
            print("app: frame \(pixelSize.Width)x\(pixelSize.Height): page \(repaint ? "\(ms(t0, t1)) ms" : "kept"), viewports \(ms(t1, t2)) ms, present \(t2.Elapsed().AsMilliseconds()) ms")
        }
        if snapshotPath != nil && !done && snapshotAfter > 0 && snapshotBegun.Elapsed().AsSeconds() < snapshotAfter {
            // Not yet: keep frames coming until it is time.
            requestFrame()
        } else if let path = snapshotPath, !done {
            try? fs.WriteFile(fs.Path(path), png.Encode(image.RGBA(width: int(pixelSize.Width), height: int(pixelSize.Height), pixels: pixels)))
            done = true
            win.RequestFrame()
        }
    }

    /// Takes a window event; false when the app should end.
    func handle(_ event: window.Event) -> bool {
        switch event {
        case .closeRequested:
            // The app may ask first (unsaved work, running programs).
            if let ask = closeHandler, !ask() {
                requestFrame()
                return true
            }
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
        let t0 = time.Instant.Now()
        state.Batch { _ = self.view.Handle(event) }
        if trace {
            let ms = t0.Elapsed().AsMilliseconds()
            if ms >= 2 { print("app: event took \(ms) ms") }
        }
        let c = view.DesiredCursor()
        if c != cursor {
            cursor = c
            win.SetCursor(c)
        }
        if view.NeedsRepaint() || view.NeedsAnimation() || viewport.Wanted() { requestFrame() }
        return true
    }
}

// Set by Quit, from the UI thread.
var quitting = false

// What OnCloseRequest gave: asked before the window closes.
var closeHandler: (() -> bool)? = nil

/// OnCloseRequest gives a function asked when the user closes the window
/// (its close button, ⌘Q): true lets it close, false keeps it open (to
/// ask first, and Quit later).
@MainActor
public func OnCloseRequest(_ f: (() -> bool)?) {
    closeHandler = f
}

/// SetFullscreen puts the window on its own space, filling the screen,
/// or back.
@MainActor
public func SetFullscreen(_ on: bool) {
    current?.win.SetFullscreen(on)
}

/// IsFullscreen is whether the window fills the screen.
@MainActor
public func IsFullscreen() -> bool {
    return current?.win.Fullscreen() ?? false
}

/// SetAlwaysOnTop keeps the window over other apps' windows, or not.
@MainActor
public func SetAlwaysOnTop(_ on: bool) {
    current?.win.SetAlwaysOnTop(on)
}

/// SetOpacity makes the whole window translucent, 0.05 to 1.
@MainActor
public func SetOpacity(_ opacity: float32) {
    current?.win.SetOpacity(opacity)
}

/// Minimize puts the window in the Dock.
@MainActor
public func Minimize() {
    current?.win.Minimize()
}

/// SetSize resizes the window's content, in points.
@MainActor
public func SetSize(width: float32, height: float32) {
    current?.win.SetSize(window.Size(width, height))
}

/// StartWindowDrag moves the window with the pointer, from the press in
/// progress: for a page that draws its own title bar (`unifiedTitlebar`),
/// called when an empty part of it is pressed.
@MainActor
public func StartWindowDrag() {
    current?.win.StartDrag()
}

/// TitlebarDoubleClick zooms or minimizes the window, as the user set a
/// title bar's double-click to.
@MainActor
public func TitlebarDoubleClick() {
    current?.win.TitlebarDoubleClick()
}

/// SetTitlebarBand places the window buttons, with a unified title bar:
/// x points from the left, centered in a band band points tall.
@MainActor
public func SetTitlebarBand(x: float32, band: float32) {
    current?.win.SetTitlebarBand(x: x, band: band)
}

/// Beep plays the system's alert sound.
public func Beep() {
    window.Beep()
}

// The running app's host, for RequestFrame.
var current: Host? = nil

/// RequestFrame asks for a frame of the running app: what a task that
/// changed state outside an event (data that arrived, a timer) calls so
/// the change is shown. Events and viewports' Invalidate ask by
/// themselves.
@MainActor
public func RequestFrame() {
    current?.requestFrame()
}

/// IsDark is whether the running app is shown in a dark color scheme:
/// the system's appearance, or what --dark or --light asked for. What a
/// viewport that draws itself follows, as the page's prefers-color-scheme
/// does.
@MainActor
public func IsDark() -> bool {
    return current?.view.Page.IsDark ?? false
}

/// SetTitle changes the running app's window title.
@MainActor
public func SetTitle(_ title: string) {
    current?.win.SetTitle(title)
}

/// Quit ends the running app after the event or frame being handled, as
/// closing its window would.
public func Quit() {
    quitting = true
}

func ms(_ a: time.Instant, _ b: time.Instant) -> int64 {
    return (b - a).AsMilliseconds()
}

/// The page's own styles, under the app's: the system font, and no margin
/// around the body.
let baseCSS = "html { font: 14px system-ui; } body { margin: 0; }\n"

/// Opens a window titled title, mounts root in it, and runs until the
/// window is closed. Answers the program's exit status.
@MainActor
public func Run(title: string, width: float32 = 800, height: float32 = 600, css: string = "", unifiedTitlebar: bool = false,
                _ root: () -> component.Node) async -> int32 {
    var options = window.Options()
    options.MinSize = window.Size(240, 160)
    options.UnifiedTitlebar = unifiedTitlebar
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
    current = host
    viewport.SetWaker { host.requestFrame() }
    // --snapshot out.png draws a frame and quits; --dark and --light
    // show the app in that appearance, whatever the system's.
    var forced: bool? = nil
    var args = CommandLine.arguments
    var i = 1
    while i < args.count {
        if args[i] == "--snapshot" && i + 1 < args.count {
            host.snapshotPath = args[i + 1]
            i += 1
        } else if args[i] == "--snapshot-after" && i + 1 < args.count {
            host.snapshotAfter = float64(args[i + 1]) ?? 0
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
    // VSX_QUIT_AFTER=seconds: quit by itself, for timing an app unattended.
    let quitAfter = float64(env.Get("VSX_QUIT_AFTER") ?? "") ?? 0
    let begun = time.Instant.Now()
    while let event = await win.WaitEvent() {
        if quitAfter > 0 && begun.Elapsed().AsSeconds() > quitAfter { quitting = true }
        if !host.handle(event) || host.done || quitting {
            quitting = false
            viewport.SetWaker(nil)
            current = nil
            host.mounted?.Unmount()
            win.Close()
            return 0
        }
    }
    return 0
}
