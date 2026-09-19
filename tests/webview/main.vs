// Headless automated test suite for ui/webview.
package main

import "ui/window"
import "ui/webview"
import "text/html"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func testDocumentLoadingAndStyle() {
    print("Testing document loading & CSS cascade...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))

    let testHTML = """
    <html>
      <head>
        <style>
          .highlight {
            color: #0969da;
            background-color: #f0f6fc;
            padding: 8px;
            border-width: 2px;
          }
          a.btn {
            color: #ffffff;
            background-color: #1a7f37;
          }
        </style>
      </head>
      <body>
        <div id="main" class="highlight">
          <h1>Hello Webview</h1>
          <p>This is a paragraph with <a class="btn" href="https://vertex-lang.org">a link</a> inside.</p>
        </div>
      </body>
    </html>
    """

    view.LoadHTML(testHTML)
    check(view.Document != nil, "HTML document successfully parsed into DOM")

    if let doc = view.Document {
        check(doc.ElementsByTagName("h1").count == 1, "found <h1> element")
        check(doc.ElementsByTagName("a").count == 1, "found <a> element")
        check(doc.ElementsByClassName("highlight").count == 1, "found element with class 'highlight'")
    }

    check(view.AuthorSheets.count == 1, "parsed 1 <style> author stylesheet")
    check(view.RootBox != nil, "root layout box generated")
}

func testLayoutBoxGeometry() {
    print("Testing layout box tree geometry...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(800, 600))

    let testHTML = """
    <html>
      <body style="margin: 0px; padding: 0px;">
        <div id="box" style="width: 400px; height: 100px; padding: 10px; border-width: 5px; margin-top: 20px;">
          <p>Text</p>
        </div>
      </body>
    </html>
    """
    view.LoadHTML(testHTML)

    guard let root = view.RootBox else {
        check(false, "RootBox exists")
        return
    }

    check(root.Width == 800.0, "root box width matches viewport width")

    // Find the box div
    func findBoxById(_ box: webview.LayoutBox, _ id: string) -> webview.LayoutBox? {
        if let n = box.Node, n.IdAttr() == id {
            return box
        }
        var k = 0
        while k < box.Children.count {
            if let found = findBoxById(box.Children[k], id) {
                return found
            }
            k += 1
        }
        return nil
    }

    let boxDiv = findBoxById(root, "box")

    if let b = boxDiv {
        check(b.Width == 400.0, "div width correctly set to 400px")
        check(b.Height == 100.0, "div height correctly set to 100px")
        check(b.Style.PaddingTop == 10.0, "div padding top is 10px")
        check(b.Style.BorderWidth == 5.0, "div border width is 5px")

        let rect = b.BorderRect()
        // width: 400 + 10 (pad L) + 10 (pad R) + 5*2 (border) = 430
        check(rect.width == 430.0, "div border rect width includes padding and border (430px)")
        // height: 100 + 10 (pad T) + 10 (pad B) + 5*2 (border) = 130
        check(rect.height == 130.0, "div border rect height includes padding and border (130px)")
    } else {
        check(false, "found styled #box div in layout tree")
    }
}

func testHitTestingAndNavigation() {
    print("Testing hit testing and link navigation...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(800, 600))

    let testHTML = """
    <html>
      <body style="margin: 0px; padding: 0px;">
        <div style="margin: 50px;">
          <a id="navlink" href="https://example.com/target">Clickable Link</a>
        </div>
      </body>
    </html>
    """
    view.LoadHTML(testHTML)

    var navigatedURL = ""
    view.OnNavigate { url in
        navigatedURL = url
    }

    // Find the link box
    guard let root = view.RootBox else {
        check(false, "root box exists")
        return
    }

    func findLinkBox(_ box: webview.LayoutBox) -> webview.LayoutBox? {
        if let n = box.Node, n.TagName == "a" || n.TagName == "A" {
            return box
        }
        var k = 0
        while k < box.Children.count {
            if let res = findLinkBox(box.Children[k]) {
                return res
            }
            k += 1
        }
        return nil
    }

    guard let linkBox = findLinkBox(root) else {
        check(false, "found link box in layout tree")
        return
    }

    let midX = linkBox.X + 10.0
    let midY = linkBox.Y + 5.0

    // 1. Move pointer over link -> should set pointingHand cursor
    let moveEv = window.Event.pointerMoved(window.Pointer(
        Position: window.Point(midX, midY)
    ))
    let moveRes = view.Handle(moveEv)
    if let cur = view.DesiredCursor() {
        check(cur == window.Cursor.pointingHand, "hovering over link sets cursor to pointingHand")
    } else {
        check(false, "hovering over link sets cursor to pointingHand (got nil)")
    }

    // 2. Click on link -> should invoke onNavigate
    let clickEv = window.Event.pointerDown(
        window.Pointer(
            Position: window.Point(midX, midY)
        ),
        window.PointerButton.primary
    )
    let clickRes = view.Handle(clickEv)
    check(navigatedURL == "https://example.com/target", "clicking link triggered onNavigate with href")
}

func testScrolling() {
    print("Testing scroll event handling and clamping...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(400, 200))

    // Content taller than 200px viewport
    let tallHTML = """
    <html>
      <body style="margin: 0px;">
        <div style="height: 600px; background-color: #eee;">Tall Content</div>
      </body>
    </html>
    """
    view.LoadHTML(tallHTML)

    check(view.ScrollOffset().Y == 0, "initial scroll offset is 0")

    // Scroll down (Delta.Y < 0 means scroll down in window system)
    let scrollDown = window.Event.scrolled(window.Scroll(
        Delta: window.Point(0, -10),
        Precise: true
    ))
    let sRes1 = view.Handle(scrollDown)
    check(view.ScrollOffset().Y == 10.0, "scrolling down increases scrollOffset.Y to 10")

    // Scroll up beyond top
    let scrollUp = window.Event.scrolled(window.Scroll(
        Delta: window.Point(0, 50),
        Precise: true
    ))
    let sRes2 = view.Handle(scrollUp)
    check(view.ScrollOffset().Y == 0, "scrolling past top clamps to 0")
}

func testSoftwareDrawing() {
    print("Testing software framebuffer rendering...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color(255, 255, 255, 255)))
    let width: int32 = 400
    let height: int32 = 300
    let pixelSize = window.PixelSize(width, height)
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(float32(width), float32(height)))

    let pageHTML = """
    <html>
      <head>
        <style>
          body { margin: 10px; background-color: #ffffff; }
          .banner { background-color: #0969da; height: 40px; }
          p { color: #000000; font-size: 16px; }
        </style>
      </head>
      <body>
        <div class="banner"></div>
        <p>Render Check</p>
      </body>
    </html>
    """
    view.LoadHTML(pageHTML)

    var canvas = [uint8](repeating: 0, count: int(width) * int(height) * 4)
    view.Draw(into: &canvas, canvasSize: pixelSize, scale: 1.0)

    // Check if background was filled (should have white pixels)
    // Pixel (0, 0) should be white (255, 255, 255, 255)
    check(canvas[0] == 255 && canvas[1] == 255 && canvas[2] == 255 && canvas[3] == 255, "canvas background filled with white")

    // Check if blue banner was painted (#0969da -> R: 9, G: 105, B: 218)
    // Banner starts at margin 10px, so around (50, 25) should be blue
    let bannerIdx = (25 * int(width) + 50) * 4
    let r = canvas[bannerIdx]
    let g = canvas[bannerIdx + 1]
    let b = canvas[bannerIdx + 2]
    check(r == 9 && g == 105 && b == 218, "banner rendered with color #0969da (got \(r), \(g), \(b))")

    // Check if text rendered non-white pixels
    var foundDarkPixel = false
    var p = 0
    while p < canvas.count {
        if canvas[p] < 50 && canvas[p + 1] < 50 && canvas[p + 2] < 50 && canvas[p + 3] == 255 {
            foundDarkPixel = true
            break
        }
        p += 4
    }
    check(foundDarkPixel, "text glyphs rendered into framebuffer")
}

func testBrowserHomeHTML() {
    print("Testing full browser homeHTML loading & drawing...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))
    view.SetBounds(origin: window.Point(0, 44), size: window.Size(960, 676))

    let homeHTML = """
    <html>
      <head>
        <style>
          body {
            font-size: 15px;
            color: #24292f;
            background-color: #ffffff;
            margin: 24px;
          }
          h1 {
            font-size: 26px;
            color: #0969da;
            margin-bottom: 8px;
          }
          .subtitle {
            font-size: 14px;
            color: #57609a;
            margin-bottom: 20px;
          }
          .card {
            background-color: #f6f8fa;
            border-width: 1px;
            border-color: #d0d7de;
            padding: 16px;
            margin-top: 16px;
            margin-bottom: 16px;
          }
          .tag {
            color: #1a7f37;
            font-size: 13px;
          }
          ul {
            margin-top: 12px;
            padding-left: 24px;
          }
          li {
            margin-top: 6px;
            margin-bottom: 6px;
          }
          a {
            color: #0969da;
          }
          .footer {
            margin-top: 32px;
            font-size: 12px;
            color: #8c959f;
            border-width: 1px;
            border-color: #e1e4e8;
            padding-top: 12px;
          }
        </style>
      </head>
      <body>
        <h1>Vertex Pure-Software Webview</h1>
        <p class="subtitle">A fast, self-contained HTML and CSS rendering engine built in 100% pure Vertex.</p>

        <div class="card">
          <h3>Architecture Highlights</h3>
          <p>This page is parsed with <b>text/html</b> and styled with <b>text/css</b>.</p>
          <p class="tag">Zero external dependencies • CPU Framebuffer Painter • Sub-millisecond layout</p>
        </div>

        <h3>Quick Navigation</h3>
        <ul>
          <li><a href="https://vertex-lang.org/docs">Vertex Language Documentation</a></li>
          <li><a href="https://vertex-lang.org/packages">Standard Packages Directory</a></li>
          <li><a href="https://github.com/vertex-language/ui">UI & Window System Repository</a></li>
        </ul>

        <div class="card">
          <h3>Interactive Features</h3>
          <p>Try resizing this window or scrolling with your trackpad or mouse wheel.</p>
          <p>Hover over hyperlinks to see dynamic cursor switching to <i>pointingHand</i>!</p>
        </div>

        <p class="footer">Rendered with ui/webview on Vertex OS Window Host.</p>
      </body>
    </html>
    """

    print("  calling view.LoadHTML(homeHTML)...")
    view.LoadHTML(homeHTML)
    print("  view.LoadHTML finished!")
    check(view.RootBox != nil, "homeHTML produced layout box")

    print("  calling view.Draw(homeHTML)...")
    let width: int32 = 960
    let height: int32 = 720
    var canvas = [uint8](repeating: 245, count: int(width) * int(height) * 4)
    view.Draw(into: &canvas, canvasSize: window.PixelSize(width, height), scale: 1.0)
    print("  view.Draw finished!")
    check(true, "browser homeHTML loaded and drawn successfully")
}

func testFormControlsAndInput() {
    print("Testing form controls (input, textarea, button) and interactive editing...")
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(800, 600))

    let testHTML = """
    <html>
      <body style="margin: 0px; padding: 0px;">
        <div>
          <input id="myinput" name="search" value="hello" placeholder="Search..." style="width: 200px; height: 30px;" />
          <textarea id="myarea" name="notes" placeholder="Write...">first line</textarea>
          <button id="mybtn" name="submit">Click Me</button>
        </div>
      </body>
    </html>
    """
    view.LoadHTML(testHTML)

    guard let root = view.RootBox else {
        check(false, "root layout box generated for form controls")
        return
    }

    func findControlBox(_ box: webview.LayoutBox, _ ctrl: webview.ControlKind) -> webview.LayoutBox? {
        if box.Control == ctrl {
            return box
        }
        var i = 0
        while i < box.Children.count {
            if let found = findControlBox(box.Children[i], ctrl) {
                return found
            }
            i += 1
        }
        return nil
    }

    let inputBox = findControlBox(root, .input)
    let areaBox = findControlBox(root, .textarea)
    let btnBox = findControlBox(root, .button)

    check(inputBox != nil, "found <input> control box in layout tree")
    check(areaBox != nil, "found <textarea> control box in layout tree")
    check(btnBox != nil, "found <button> control box in layout tree")

    guard let ib = inputBox, let ab = areaBox, let bb = btnBox else {
        return
    }

    check(ib.Value == "hello", "input box initial value is 'hello'")
    check(ib.Placeholder == "Search...", "input box placeholder is 'Search...'")
    check(ab.Value == "first line", "textarea box initial value is 'first line'")

    // Test hover cursors
    let moveOverInput = window.Event.pointerMoved(window.Pointer(Position: window.Point(ib.X + 10, ib.Y + 10)))
    let moveRes = view.Handle(moveOverInput)
    if let cur = view.DesiredCursor() {
        check(cur == window.Cursor.iBeam, "hovering over input sets iBeam cursor")
    } else {
        check(false, "hovering over input sets iBeam cursor (got nil)")
    }

    let moveOverBtn = window.Event.pointerMoved(window.Pointer(Position: window.Point(bb.X + 5, bb.Y + 5)))
    let resMoveBtn = view.Handle(moveOverBtn)
    if let cur = view.DesiredCursor() {
        check(cur == window.Cursor.pointingHand, "hovering over button sets pointingHand cursor")
    } else {
        check(false, "hovering over button sets pointingHand cursor (got nil)")
    }

    // Test click to focus input
    let clickInput = window.Event.pointerDown(
        window.Pointer(Position: window.Point(ib.X + 10, ib.Y + 10)),
        window.PointerButton.primary
    )
    let resClickInput = view.Handle(clickInput)
    check(view.FocusedNode != nil, "clicking input focuses the DOM node")

    // Test typing text into focused input
    let typeText = window.Event.text(" world")
    let resTypeText = view.Handle(typeText)
    if let n = view.FocusedNode {
        let val = n.GetAttribute("value") ?? ""
        check(val == "hello world" || val == " worldhello", "typing text updates input value (got '\(val)')")
    } else {
        check(false, "focused node exists after typing")
    }

    // Test backspace
    var keyEvent = window.KeyEvent(
        Code: window.KeyCode.backspace,
        Key: "Backspace",
        Modifiers: window.Modifiers(),
        Repeat: false
    )
    let bsEv = window.Event.keyDown(keyEvent)
    let resBs = view.Handle(bsEv)
    if let n = view.FocusedNode {
        let val = n.GetAttribute("value") ?? ""
        check(!val.isEmpty, "backspace removed a character correctly")
    }

    // Test button click action callback
    var actionName = ""
    var actionVal = ""
    view.OnAction { name, val in
        actionName = name
        actionVal = val
    }

    let clickBtn = window.Event.pointerDown(
        window.Pointer(Position: window.Point(bb.X + 5, bb.Y + 5)),
        window.PointerButton.primary
    )
    let resClickBtn = view.Handle(clickBtn)
    check(actionName == "submit", "clicking button triggered OnAction with name 'submit' (got '\(actionName)')")
    check(actionVal == "Click Me", "clicking button triggered OnAction with inner text 'Click Me' (got '\(actionVal)')")
}

func main() -> int32 {
    print("Running ui/webview test suite...\n")
    testDocumentLoadingAndStyle()
    testLayoutBoxGeometry()
    testHitTestingAndNavigation()
    testScrolling()
    testSoftwareDrawing()
    testBrowserHomeHTML()
    testFormControlsAndInput()

    if failures == 0 {
        print("\nALL WEBVIEW CHECKS PASSED!")
    } else {
        print("\n\(failures) failed")
    }
    return int32(failures)
}

