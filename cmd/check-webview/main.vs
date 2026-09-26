// The web view checked headless: a page placed in a window, driven by
// the window's events.
package main

import (
    "image/draw"
    "ui/webview"
    "ui/window"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func pixelAt(_ pixels: [uint8], _ w: int32, _ x: int32, _ y: int32) -> draw.Color {
    let i = int((y * w + x) * 4)
    return draw.Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}

func countDark(_ pixels: [uint8], _ w: int32, _ r: draw.IRect) -> int {
    var n = 0
    var y = r.Y
    while y < r.Bottom {
        var x = r.X
        while x < r.Right {
            let c = pixelAt(pixels, w, x, y)
            if int(c.R) + int(c.G) + int(c.B) < 300 { n += 1 }
            x += 1
        }
        y += 1
    }
    return n
}

@MainActor
func testView() {
    print("The view")
    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 20), size: window.Size(300, 200))
    view.Page.LoadHTML("""
    <title>Page One</title>
    <body style="margin:0">
      <div id=red style="background:red;width:100px;height:50px;border-radius:0"></div>
      <p id=text style="margin:10px 0;font-size:16px">Hello <a id=link href="page2.html">link</a></p>
      <div style="background:#00f;width:50px;height:20px;margin-left:100px"></div>
      <input id=field name=q value="ab">
      <button id=btn name=go value=1>Go</button>
      <div style="height:600px"></div>
    </body>
    """, baseURL: "/site/")
    check(view.Page.Title == "Page One", "the title is read (got \(view.Page.Title))")
    let w: int32 = 300
    let h: int32 = 240
    var pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 10, 30) == draw.Color(255, 0, 0), "the red box is painted at the view's origin (got \(pixelAt(pixels, w, 10, 30).R) \(pixelAt(pixels, w, 10, 30).G))")
    check(pixelAt(pixels, w, 150, 30) == draw.Color.white, "beside the box is the page background")
    check(pixelAt(pixels, w, 10, 5) == draw.Color(0, 0, 0, 0), "nothing is painted above the view")
    let p = view.Page.BoxFor(view.Page.QuerySelector("#text")!)!
    let textRow = draw.IRect(0, int32(p.Y + 20), 60, int32(p.Height))
    check(countDark(pixels, w, textRow) > 30, "text is painted (\(countDark(pixels, w, textRow)) dark pixels)")
    let blueY = int32(p.Y + p.Height + 20 + 15)
    check(pixelAt(pixels, w, 120, blueY) == draw.Color(0, 0, 255), "a later block lands below the paragraph (got y \(blueY))")
    check(view.Page.ContentSize().Height > 600, "the content is taller than the view")
    check(!view.NeedsRepaint(), "drawing clears the repaint flag")

    // Hovering and clicking the link.
    let linkBox = view.Page.BoxFor(view.Page.QuerySelector("#link")!)!
    let linkRect = view.Page.RootBox!.Lines.isEmpty ? draw.Rect.zero : draw.Rect.zero
    _ = linkRect
    var linkX: float32 = 0
    var linkY: float32 = 0
    for line in p.Lines {
        for sp in line.Spans {
            if sp.Box.Id == linkBox.Id {
                linkX = sp.X + sp.Width / 2
                linkY = line.Y + line.Height / 2
            }
        }
    }
    let over = window.Point(linkX, linkY + 20 + p.Y)
    _ = view.Handle(.pointerMoved(window.Pointer(Position: over)))
    check(view.DesiredCursor() == window.Cursor.pointingHand, "hovering a link asks for a hand (at \(over.X) \(over.Y))")
    var hovered: string? = "unset"
    view.Page.OnHoverLink { url in hovered = url }
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(250, 30))))
    _ = view.Handle(.pointerMoved(window.Pointer(Position: over)))
    check(hovered == "/site/page2.html", "hovering reports the resolved link (got \(hovered ?? "nil"))")
    check(view.ElementAt(over)?.TagName == "a", "ElementAt finds the link")
    var navigated = ""
    view.Page.OnNavigate { url in navigated = url }
    _ = view.Handle(.pointerDown(window.Pointer(Position: over), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: over), .primary))
    check(navigated == "/site/page2.html", "clicking the link navigates (got \(navigated))")
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(10, 30))))
    check(view.DesiredCursor() == window.Cursor.arrow, "off the link the cursor is an arrow")

    // A double click on "Hello" selects the word; a triple the paragraph.
    let wordAt = window.Point(12, p.Y + p.Height / 2 + 20)
    _ = view.Handle(.pointerDown(window.Pointer(Position: wordAt, Clicks: 2), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: wordAt, Clicks: 2), .primary))
    check(view.Page.SelectedText() == "Hello", "a double click selects the word (got '\(view.Page.SelectedText())')")
    _ = view.Handle(.pointerDown(window.Pointer(Position: wordAt, Clicks: 3), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: wordAt, Clicks: 3), .primary))
    check(view.Page.SelectedText() == "Hello link", "a triple click selects the paragraph (got '\(view.Page.SelectedText())')")
    view.Page.ClearSelection()

    // Typing in the field.
    let field = view.Page.QuerySelector("#field")!
    let fieldBox = view.Page.BoxFor(field)!
    let fieldPos = window.Point(fieldBox.X + 5, fieldBox.Y + fieldBox.Height / 2 + 20)
    var fpX = fieldBox.X
    var fpY = fieldBox.Y
    var parent = fieldBox.Parent
    while let pb = parent { fpX += pb.X; fpY += pb.Y; parent = pb.Parent }
    let inField = window.Point(fpX + fieldBox.Width - 5, fpY + fieldBox.Height / 2 + 20)
    _ = fieldPos
    _ = view.Handle(.pointerDown(window.Pointer(Position: inField), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: inField), .primary))
    check(view.Page.FocusedElement?.Id == field.Id, "clicking a field focuses it")
    _ = view.Handle(.text("c"))
    check(view.Page.ValueOf(field) == "abc", "typing appends at the caret (got \(view.Page.ValueOf(field)))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .arrowLeft, Key: "ArrowLeft", Modifiers: window.Modifiers(), Repeat: false)))
    _ = view.Handle(.text("X"))
    check(view.Page.ValueOf(field) == "abXc", "the caret moves with the arrows (got \(view.Page.ValueOf(field)))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .backspace, Key: "Backspace", Modifiers: window.Modifiers(), Repeat: false)))
    check(view.Page.ValueOf(field) == "abc", "backspace deletes before the caret (got \(view.Page.ValueOf(field)))")
    var action = ""
    view.Page.OnAction { name, value in action = name + "=" + value }
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .enter, Key: "Enter", Modifiers: window.Modifiers(), Repeat: false)))
    check(action == "q=abc", "Enter in a field outside a form reports an action (got \(action))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .tab, Key: "Tab", Modifiers: window.Modifiers(), Repeat: false)))
    let focusedTag = view.Page.FocusedElement?.TagName
    check(focusedTag == "button", "Tab moves focus to the button (got \(focusedTag ?? "nil"))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .enter, Key: "Enter", Modifiers: window.Modifiers(), Repeat: false)))
    check(action == "go=1", "Enter on a button presses it (got \(action))")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(countDark(pixels, w, draw.IRect(int32(fpX), int32(fpY + 20), int32(fieldBox.Width), int32(fieldBox.Height))) > 10, "the field's text is painted")

    // Scrolling.
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(150, 100))))
    _ = view.Handle(.scrolled(window.Scroll(Delta: window.Point(0, -3), Precise: false)))
    check(view.Page.ScrollOffset().Y == 120, "a wheel step scrolls 40 points a line (got \(view.Page.ScrollOffset().Y))")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 10, 30) == draw.Color.white, "after scrolling the red box has moved up out of view")
    _ = view.Handle(.scrolled(window.Scroll(Delta: window.Point(0, 100), Precise: false)))
    check(view.Page.ScrollOffset().Y == 0, "scrolling up stops at the top")
    view.Page.SetScrollOffset(draw.Point(0, 10000))
    check(near(view.Page.ScrollOffset().Y, view.Page.ContentSize().Height - 200), "scrolling down stops at the bottom")

    // Resizing relayouts.
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(150, 200))
    let narrow = view.Page.BoxFor(view.Page.QuerySelector("#text")!)!
    check(narrow.Width == 150, "a narrower view lays out narrower (got \(narrow.Width))")

    // Loading another page resets state.
    view.Page.LoadHTML("<body style='margin:0;background:#123456'><h1>Two</h1></body>")
    check(view.Page.ScrollOffset().Y == 0 && view.Page.FocusedElement == nil, "a new page starts unscrolled and unfocused")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 140, 190) == draw.Color(0x12, 0x34, 0x56), "the body's background fills the view")
}

func near(_ a: float32, _ b: float32, _ tolerance: float32 = 0.5) -> bool {
    let d = a - b
    return d < tolerance && d > -tolerance
}

func main() -> int32 {
    testView()
    if failures == 0 {
        print("ALL WEBVIEW CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
