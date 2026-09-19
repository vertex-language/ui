// A lightweight desktop HTML/CSS browser powered by ui/webview.
package main

import "ui/window"
import "ui/webview"



func main() async -> int32 {
    var options = window.Options()
    options.MinSize = window.Size(400, 300)

    let w: window.Window
    do {
        w = try window.Create(title: "Vertex Browser", size: window.Size(960, 720), options: options)
    } catch let e as window.WindowError {
        print("failed to create window: \(e.Message)")
        return 1
    } catch {
        return 1
    }

    var pixelSize = w.PixelSize()
    var pixels = [uint8](repeating: 245, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
    let surface = w.Surface()
    var currentCursor = window.Cursor.arrow

    // Initialize the webview component
    let view = webview.WebView(configuration: webview.Config(backgroundColor: webview.Color.white))

    let chromeHeight: float32 = 44.0
    let initialWinSize = w.Size()
    view.SetBounds(
        origin: window.Point(0, chromeHeight),
        size: window.Size(initialWinSize.Width, initialWinSize.Height - chromeHeight)
    )

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

        <div class="card">
          <h3>Interactive Form Controls</h3>
          <p>Click inside the input or textarea to type, navigate with arrow keys, and backspace:</p>
          <div style="margin-top: 10px; margin-bottom: 12px;">
            <input name="search" placeholder="Type a search query..." style="padding: 8px 12px; font-size: 14px; width: 340px;" />
          </div>
          <div style="margin-bottom: 12px;">
            <textarea name="feedback" placeholder="Write multiple lines of text here..." style="padding: 8px 12px; font-size: 14px; width: 440px; height: 72px;"></textarea>
          </div>
          <div>
            <button name="submit" style="padding: 8px 16px; background-color: #0969da; color: #ffffff; border-radius: 6px; font-size: 14px;">Send Feedback</button>
          </div>
        </div>

        <p class="footer">Rendered with ui/webview on Vertex OS Window Host.</p>
      </body>
    </html>
    """

    view.LoadHTML(homeHTML)

    view.OnAction { name, value in
        print("Action triggered from [\(name)]: '\(value)'")
    }

    var currentURL = "about:home"
    view.OnNavigate { url in
        print("Navigate clicked: \(url)")
        currentURL = url
        // Load a navigation confirmation page
        let navHTML = """
        <html>
          <body style="margin: 24px; font-size: 16px; color: #24292f;">
            <h1 style="color: #0969da;">Navigation Requested</h1>
            <p>You clicked a link pointing to:</p>
            <div style="background-color: #ddf4ff; border: 1px; border-color: #54aeff; padding: 12px; margin: 16px 0;">
              <b>\(url)</b>
            </div>
            <p><a href="about:home">Back to Home</a></p>
          </body>
        </html>
        """
        if url == "about:home" {
            view.LoadHTML(homeHTML)
        } else {
            view.LoadHTML(navHTML)
        }
        w.RequestFrame()
    }

    w.RequestFrame()

    while let event = await w.WaitEvent() {
        switch event {
        case .closeRequested:
            w.Close()
            return 0

        case .keyDown(let k):
            if k.Code == .escape {
                w.Close()
                return 0
            }
            let res = view.Handle(event)
            if res == .handled || view.NeedsRepaint() {
                w.RequestFrame()
            }

        case .text(_):
            let res = view.Handle(event)
            if res == .handled || view.NeedsRepaint() {
                w.RequestFrame()
            }

        case .resized(let sz):
            let newPx = w.PixelSize()
            if newPx.Width != pixelSize.Width || newPx.Height != pixelSize.Height {
                pixelSize = newPx
                pixels = [uint8](repeating: 245, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
            }
            view.SetBounds(
                origin: window.Point(0, chromeHeight),
                size: window.Size(sz.Width, sz.Height - chromeHeight)
            )
            w.RequestFrame()

        case .scaleFactorChanged(_):
            let newPx = w.PixelSize()
            if newPx.Width != pixelSize.Width || newPx.Height != pixelSize.Height {
                pixelSize = newPx
                pixels = [uint8](repeating: 245, count: int(pixelSize.Width) * int(pixelSize.Height) * 4)
            }
            let sz = w.Size()
            view.SetBounds(
                origin: window.Point(0, chromeHeight),
                size: window.Size(sz.Width, sz.Height - chromeHeight)
            )
            w.RequestFrame()

        case .pointerMoved(_):
            let _ = view.Handle(event)
            if let cur = view.DesiredCursor() {
                if cur != currentCursor {
                    currentCursor = cur
                    w.SetCursor(cur)
                }
            }

        case .pointerDown(_, _), .pointerUp(_, _):
            let res = view.Handle(event)
            if let cur = view.DesiredCursor() {
                if cur != currentCursor {
                    currentCursor = cur
                    w.SetCursor(cur)
                }
            }
            if res == .handled || view.NeedsRepaint() {
                w.RequestFrame()
            }

        case .scrolled(_):
            let res = view.Handle(event)
            if res == .handled || view.NeedsRepaint() {
                w.RequestFrame()
            }

        case .frame(_):
            let scale = w.ScaleFactor()
            let cHeightPx = int32(chromeHeight * scale)
            let curW = pixelSize.Width
            let curH = pixelSize.Height

            // 1. Draw top chrome / address bar
            webview.Painter.fillRect(
                into: &pixels,
                bufferWidth: curW,
                bufferHeight: curH,
                x: 0,
                y: 0,
                width: curW,
                height: cHeightPx,
                color: webview.Color(r: 235, g: 238, b: 242, a: 255),
                clipX: 0,
                clipY: 0,
                clipWidth: curW,
                clipHeight: curH
            )
            // Address bar border
            webview.Painter.fillRect(
                into: &pixels,
                bufferWidth: curW,
                bufferHeight: curH,
                x: 0,
                y: cHeightPx - 1,
                width: curW,
                height: 1,
                color: webview.Color(r: 208, g: 215, b: 222, a: 255),
                clipX: 0,
                clipY: 0,
                clipWidth: curW,
                clipHeight: curH
            )
            // Address bar URL background
            let urlBoxPad: int32 = int32(6 * scale)
            let urlBoxX = int32(16 * scale)
            let urlBoxW = curW - int32(32 * scale)
            let urlBoxH = cHeightPx - urlBoxPad * 2
            webview.Painter.fillRect(
                into: &pixels,
                bufferWidth: curW,
                bufferHeight: curH,
                x: urlBoxX,
                y: urlBoxPad,
                width: urlBoxW,
                height: urlBoxH,
                color: webview.Color.white,
                clipX: 0,
                clipY: 0,
                clipWidth: curW,
                clipHeight: curH
            )
            // Address bar URL text
            webview.FontRenderer.DrawText(
                into: &pixels,
                bufferWidth: curW,
                bufferHeight: curH,
                x: urlBoxX + int32(8 * scale),
                y: urlBoxPad + int32(6 * scale),
                text: currentURL,
                color: webview.Color(r: 60, g: 65, b: 70, a: 255),
                fontSize: 13.0,
                scale: scale
            )

            // 2. Draw webview layout into canvas
            view.Draw(into: &pixels, canvasSize: pixelSize, scale: scale)

            // 3. Present pixels
            do {
                try surface.Present(pixels, size: pixelSize)
            } catch let e as window.WindowError {
                print("present error: \(e.Message)")
            } catch {
            }

        default:
            break
        }
    }

    return 0
}
