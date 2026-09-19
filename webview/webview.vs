package webview

import "ui/window"
import "text/html"
import "text/css"

public struct Config {
    public var BaseURL: string?
    public var BackgroundColor: Color

    public init(baseURL: string? = nil, backgroundColor: Color = .white) {
        self.BaseURL = baseURL
        self.BackgroundColor = backgroundColor
    }

    public static func Default() -> Config {
        return Config(baseURL: nil, backgroundColor: Color.white)
    }
}

public enum EventResult: Equatable {
    case handled
    case ignored
}

/// An embedded webview component that parses, lays out, and paints HTML and CSS.
public class WebView {
    public var Configuration: Config
    public var Document: html.Document?
    public var RootBox: LayoutBox?
    public var AuthorSheets: [css.StyleSheet]

    var styleEngine: StyleEngine
    var layoutEngine: LayoutEngine

    var origin: window.Point
    var size: window.Size
    var scrollOffset: window.Point
    var contentHeight: float32
    var needsRepaint: bool
    var desiredCursor: window.Cursor?

    public var FocusedNode: html.Node?
    public var CaretIndex: int

    var onNavigate: ((string) -> Void)?
    var onAction: ((string, string) -> Void)?

    public init(configuration: Config? = nil) {
        self.Configuration = configuration ?? Config.Default()
        self.Document = nil
        self.RootBox = nil
        self.AuthorSheets = []
        self.styleEngine = StyleEngine()
        self.layoutEngine = LayoutEngine(styleEngine: self.styleEngine)
        self.origin = window.Point(0, 0)
        self.size = window.Size(800, 600)
        self.scrollOffset = window.Point(0, 0)
        self.contentHeight = 0
        self.needsRepaint = true
        self.desiredCursor = nil
        self.FocusedNode = nil
        self.CaretIndex = 0
        self.onNavigate = nil
        self.onAction = nil
    }

    // MARK: - Content Loading

    /// Loads and renders an HTML string with optional external CSS.
    public func LoadHTML(_ htmlString: string, extraCSS: string? = nil) {
        let doc = html.Parse(htmlString)
        self.Document = doc
        self.AuthorSheets = []

        // Parse any <style> tags inside the HTML document
        let styleElements = doc.ElementsByTagName("style")
        var s = 0
        while s < styleElements.count {
            let elem = styleElements[s]
            let cssText = elem.InnerText()
            if !cssText.isEmpty {
                let sheet = css.Parse(cssText)
                self.AuthorSheets.append(sheet)
            }
            s += 1
        }

        // Add additional stylesheet if passed
        if let customCSS = extraCSS {
            let extraSheet = css.Parse(customCSS)
            self.AuthorSheets.append(extraSheet)
        }

        relayout()
        self.needsRepaint = true
    }

    // MARK: - Geometry & Viewport

    public func SetBounds(origin: window.Point, size: window.Size) {
        let widthChanged = self.size.Width != size.Width
        self.origin = origin
        self.size = size
        if widthChanged && self.Document != nil {
            relayout()
        }
        self.needsRepaint = true
    }

    public func Bounds() -> (origin: window.Point, size: window.Size) {
        return (origin: origin, size: size)
    }

    public func ScrollOffset() -> window.Point {
        return scrollOffset
    }

    public func SetScrollOffset(_ offset: window.Point) {
        self.scrollOffset = offset
        clampScroll()
        self.needsRepaint = true
    }

    public func NeedsRepaint() -> bool {
        return needsRepaint
    }

    public func DesiredCursor() -> window.Cursor? {
        return desiredCursor
    }

    public func OnNavigate(_ handler: (string) -> Void) {
        self.onNavigate = handler
    }

    public func OnAction(_ handler: (string, string) -> Void) {
        self.onAction = handler
    }

    // MARK: - Event Handling

    public func Handle(_ event: window.Event) -> EventResult {
        switch event {
        case .pointerMoved(let p):
            if isPointInside(p.Position) {
                let relX = (p.Position.X - origin.X) + scrollOffset.X
                let relY = (p.Position.Y - origin.Y) + scrollOffset.Y

                if let hit = RootBox?.HitTest(px: relX, py: relY) {
                    if let linkNode = findLinkAncestor(hit.Node) {
                        desiredCursor = window.Cursor.pointingHand
                    } else if hit.Control == .button || findButtonAncestor(hit.Node) != nil {
                        desiredCursor = window.Cursor.pointingHand
                    } else if hit.Control == .input || hit.Control == .textarea || findInputAncestor(hit.Node) != nil || hit.Kind == .text {
                        desiredCursor = window.Cursor.iBeam
                    } else {
                        desiredCursor = hit.Style.HasCursor ? hit.Style.DesiredCursor : window.Cursor.arrow
                    }
                } else {
                    desiredCursor = window.Cursor.arrow
                }
                return .handled
            }

        case .pointerDown(let p, let btn):
            if isPointInside(p.Position) && btn == .primary {
                let relX = (p.Position.X - origin.X) + scrollOffset.X
                let relY = (p.Position.Y - origin.Y) + scrollOffset.Y

                if let hit = RootBox?.HitTest(px: relX, py: relY) {
                    if hit.Control == .input || hit.Control == .textarea || findInputAncestor(hit.Node) != nil {
                        var inputNode = hit.Node
                        if inputNode == nil {
                            inputNode = findInputAncestor(hit.Node)
                        }
                        FocusedNode = inputNode
                        let padX: float32 = hit.Style.PaddingLeft > 0 ? hit.Style.PaddingLeft : 8.0
                        let clickRelX = relX - (hit.X + padX)
                        let val = hit.Value
                        if clickRelX > 0 && !val.isEmpty {
                            var bestIdx = 0
                            var i = 1
                            while i <= val.utf8.count {
                                let sub = substringUpTo(val, i)
                                let m = FontRenderer.MeasureText(sub, fontSize: hit.Style.FontSize)
                                if m.width <= clickRelX {
                                    bestIdx = i
                                } else {
                                    break
                                }
                                i += 1
                            }
                            CaretIndex = bestIdx
                        } else {
                            CaretIndex = 0
                        }
                        needsRepaint = true
                        return .handled
                    } else if hit.Control == .button || findButtonAncestor(hit.Node) != nil {
                        var btnNode = hit.Node
                        if btnNode == nil {
                            btnNode = findButtonAncestor(hit.Node)
                        }
                        if let n = btnNode {
                            if let act = onAction {
                                let name = getNodeName(n, defaultName: "button")
                                act(name, n.InnerText())
                            }
                        }
                        return .handled
                    } else if let linkNode = findLinkAncestor(hit.Node) {
                        if let href = linkNode.GetAttribute("href") {
                            if let nav = onNavigate {
                                nav(href)
                            }
                        }
                        FocusedNode = nil
                        needsRepaint = true
                        return .handled
                    } else {
                        if FocusedNode != nil {
                            FocusedNode = nil
                            needsRepaint = true
                        }
                    }
                }
                return .handled
            }

        case .text(let t):
            if let node = FocusedNode {
                let isTextarea = toLower(node.TagName) == "textarea"
                let curVal = getNodeValue(node)
                let newVal = insertString(curVal, at: CaretIndex, t)
                node.SetAttribute("value", newVal)
                if isTextarea {
                    node.Text = newVal
                }
                CaretIndex += t.utf8.count
                relayout()
                needsRepaint = true
                return .handled
            }

        case .keyDown(let k):
            if let node = FocusedNode {
                let isTextarea = toLower(node.TagName) == "textarea"
                if k.Code == .backspace {
                    let curVal = getNodeValue(node)
                    let del = deleteCharBefore(curVal, at: CaretIndex)
                    node.SetAttribute("value", del.result)
                    if isTextarea {
                        node.Text = del.result
                    }
                    CaretIndex = del.newIndex
                    relayout()
                    needsRepaint = true
                    return .handled
                } else if k.Code == .arrowLeft {
                    if CaretIndex > 0 {
                        CaretIndex -= 1
                        needsRepaint = true
                    }
                    return .handled
                } else if k.Code == .arrowRight {
                    let curVal = getNodeValue(node)
                    if CaretIndex < curVal.utf8.count {
                        CaretIndex += 1
                        needsRepaint = true
                    }
                    return .handled
                } else if k.Code == .enter {
                    if isTextarea {
                        let curVal = getNodeValue(node)
                        let newVal = insertString(curVal, at: CaretIndex, "\n")
                        node.SetAttribute("value", newVal)
                        node.Text = newVal
                        CaretIndex += 1
                        relayout()
                        needsRepaint = true
                        return .handled
                    } else if let act = onAction {
                        let name = getNodeName(node, defaultName: "input")
                        let val = getNodeValue(node)
                        act(name, val)
                        return .handled
                    }
                }
            }

        case .scrolled(let s):
            let multiplier: float32 = s.Precise ? 1.0 : 24.0
            scrollOffset.Y -= s.Delta.Y * multiplier
            clampScroll()
            needsRepaint = true
            return .handled

        default:
            break
        }
        return .ignored
    }

    // MARK: - Drawing

    /// Draws the webview into the window's destination canvas at its designated bounds.
    public func Draw(into canvas: inout [uint8], canvasSize: window.PixelSize, scale: float32) {
        let viewX = int32(origin.X * scale)
        let viewY = int32(origin.Y * scale)
        let viewW = int32(size.Width * scale)
        let viewH = int32(size.Height * scale)

        // 1. Draw webview background
        if Configuration.BackgroundColor.A > 0 {
            Painter.fillRect(
                into: &canvas,
                bufferWidth: canvasSize.Width,
                bufferHeight: canvasSize.Height,
                x: viewX,
                y: viewY,
                width: viewW,
                height: viewH,
                color: Configuration.BackgroundColor,
                clipX: viewX,
                clipY: viewY,
                clipWidth: viewW,
                clipHeight: viewH
            )
        }

        // 2. Paint layout tree
        if let box = RootBox {
            let focusedId = FocusedNode?.Id ?? 0
            Painter.Paint(
                rootBox: box,
                into: &canvas,
                bufferWidth: canvasSize.Width,
                bufferHeight: canvasSize.Height,
                viewX: viewX,
                viewY: viewY,
                viewWidth: viewW,
                viewHeight: viewH,
                scrollX: scrollOffset.X,
                scrollY: scrollOffset.Y,
                scale: scale,
                focusedNodeId: focusedId,
                caretIndex: CaretIndex
            )
        }

        self.needsRepaint = false
    }

    // MARK: - Internal Helpers

    func relayout() {
        guard let doc = Document else { return }
        let result = layoutEngine.BuildLayout(
            root: doc.Root,
            authorSheets: AuthorSheets,
            viewportWidth: size.Width
        )
        self.RootBox = result.rootBox
        self.contentHeight = result.totalHeight
        clampScroll()
    }

    func clampScroll() {
        if scrollOffset.Y < 0 {
            scrollOffset.Y = 0
        }
        let maxScroll = contentHeight > size.Height ? (contentHeight - size.Height) : 0
        if scrollOffset.Y > maxScroll {
            scrollOffset.Y = maxScroll
        }
    }

    func isPointInside(_ pt: window.Point) -> bool {
        return pt.X >= origin.X && pt.X <= origin.X + size.Width &&
               pt.Y >= origin.Y && pt.Y <= origin.Y + size.Height
    }

    func findLinkAncestor(_ node: html.Node?) -> html.Node? {
        var cur = node
        while let n = cur {
            if n.Kind == html.NodeKind.element && toLower(n.TagName) == "a" && n.HasAttribute("href") {
                return n
            }
            cur = n.Parent
        }
        return nil
    }

    func findButtonAncestor(_ node: html.Node?) -> html.Node? {
        var cur = node
        while let n = cur {
            if n.Kind == html.NodeKind.element && toLower(n.TagName) == "button" {
                return n
            }
            cur = n.Parent
        }
        return nil
    }

    func findInputAncestor(_ node: html.Node?) -> html.Node? {
        var cur = node
        while let n = cur {
            if n.Kind == html.NodeKind.element {
                let tag = toLower(n.TagName)
                if tag == "input" || tag == "textarea" {
                    return n
                }
            }
            cur = n.Parent
        }
        return nil
    }
}
