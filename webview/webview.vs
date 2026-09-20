package webview

import "text/html"
import "text/css"
import "text/css/selector"
import "ui/window"
import "ui/draw"
import "fs"
import "ui/image"
import "ui/font"

/// How a view is set up.
public struct Config {
    /// Where relative URLs in the page are resolved from: a directory
    /// path or a file URL. Nil resolves nothing.
    public var BaseURL: string?
    /// What shows behind a page that sets no background.
    public var BackgroundColor: draw.Color
    /// Answers the bytes of a resource the page refers to -- a
    /// stylesheet, an image -- by its resolved URL, or nil. Without one,
    /// file paths under BaseURL are read from disk.
    public var ResourceLoader: ((string) -> [uint8]?)?

    public init(baseURL: string? = nil, backgroundColor: draw.Color = draw.Color.white) {
        BaseURL = baseURL
        BackgroundColor = backgroundColor
        ResourceLoader = nil
    }
}

public enum EventResult: Equatable {
    case handled
    case ignored
}

/// One end of a selection: a text node and a byte offset into its text.
public struct TextPosition {
    public var Node: html.Node
    public var Offset: int
}

/// A field of a submitted form.
public struct FormField {
    public var Name: string
    public var Value: string
}

/// A form submission: where it goes and what it carries.
public struct Submission {
    public var Action: string
    public var Method: string
    public var Fields: [FormField]
}

/// An HTML page inside a window: parses, styles, lays out and paints
/// what it is given, takes the window's events for the part of the
/// window it covers, and tells the host what the user did.
///
/// Everything here runs on the main thread, where the window is.
@MainActor
public final class WebView {
    public var Configuration: Config
    public var Document: html.Document?

    let resolver: StyleResolver
    let context: selector.MatchContext
    var builder: BoxTreeBuilder
    var layout: Layout? = nil
    var root: Box?
    var displayList: [PaintItem] = []
    var images: [string: draw.Image] = [:]
    var fontFaces: [string] = []

    var origin: window.Point
    var size: window.Size
    var scroll: window.Point
    var contentWidth: float32 = 0
    var contentHeight: float32 = 0

    var needsStyle = true
    var needsLayout = true
    var needsPaint = true
    var needsRepaint = true

    var hovered: html.Node? = nil
    var focused: html.Node? = nil
    var pressed: html.Node? = nil
    var caret: int = 0
    var values: [int64: string] = [:]
    var caretVisible = true
    var caretPhase: float64 = 0
    var selectionAnchor: TextPosition? = nil
    var selectionFocus: TextPosition? = nil
    var selecting = false
    var cursor: window.Cursor = window.Cursor.arrow
    var pointer: window.Point = window.Point(-1, -1)
    var baseURL: string = ""
    var title: string = ""

    var onNavigate: ((string) -> Void)? = nil
    var onSubmit: ((Submission) -> Void)? = nil
    var onAction: ((string, string) -> Void)? = nil
    var onTitle: ((string) -> Void)? = nil
    var onHoverLink: ((string?) -> Void)? = nil
    var isVisited: ((string) -> bool)? = nil

    public init(configuration: Config? = nil) {
        if let c = configuration {
            Configuration = c
        } else {
            Configuration = Config()
        }
        Document = nil
        resolver = StyleResolver(ua: UserAgentRules())
        context = selector.MatchContext()
        builder = BoxTreeBuilder(resolver: resolver, context: context)
        origin = window.Point(0, 0)
        size = window.Size(800, 600)
        scroll = window.Point(0, 0)
        baseURL = Configuration.BaseURL ?? ""
    }

    // MARK: - Loading

    /// Shows an HTML page. Its <style> elements and <link rel=stylesheet>
    /// references are read; relative references resolve against baseURL
    /// or the configuration's.
    public func LoadHTML(_ source: string, baseURL: string? = nil) {
        if let b = baseURL { self.baseURL = b }
        let doc = html.Parse(source)
        load(doc)
    }

    /// Shows an HTML file from disk; its folder is the base for what it
    /// refers to.
    public func LoadFile(_ path: string) throws {
        let bytes = try fs.ReadFile(fs.Path(path))
        let text = draw.stringOf(bytes, 0, bytes.count)
        var dir = path
        let b = [uint8](path.utf8)
        var i = b.count - 1
        while i >= 0 && b[i] != 47 { i -= 1 }
        dir = i >= 0 ? draw.stringOf(b, 0, i + 1) : ""
        LoadHTML(text, baseURL: dir)
    }

    func load(_ doc: html.Document) {
        Document = doc
        resolver.Author = RuleSet()
        fontFaces = []
        images = [:]
        // <base href> moves the base for everything that follows.
        for base in doc.ElementsByTagName("base") {
            if let href = base.GetAttribute("href"), !href.isEmpty {
                baseURL = Resolve(href)
            }
        }
        values = [:]
        focused = nil
        hovered = nil
        pressed = nil
        scroll = window.Point(0, 0)
        for head in doc.ElementsByTagName("head") {
            for child in head.Children where child.Kind == html.NodeKind.element {
                if child.TagName == "style" {
                    addSheet(css.Parse(child.InnerText()))
                } else if child.TagName == "link" {
                    let rel = lower(child.GetAttribute("rel") ?? "")
                    if rel == "stylesheet", let href = child.GetAttribute("href") {
                        if let bytes = loadResource(Resolve(href)) {
                            addSheet(css.Parse(draw.stringOf(bytes, 0, bytes.count)))
                        }
                    }
                }
            }
        }
        // Styles in the body count too, as browsers allow.
        for body in doc.ElementsByTagName("body") {
            var styles: [html.Node] = []
            collectTags(body, "style", &styles)
            for style in styles {
                addSheet(css.Parse(style.InnerText()))
            }
        }
        var wanted: [string] = []
        for img in doc.ElementsByTagName("img") {
            if let src = img.GetAttribute("src") { wanted.append(src) }
        }
        for url in resolver.Author.ImageURLs { wanted.append(url) }
        for src in wanted {
            if images[src] == nil {
                if src.hasPrefix("data:") {
                    if let decoded = image.DecodeDataURL(src) { images[src] = decoded }
                } else if let bytes = loadResource(Resolve(src)), let decoded = decodeImage(bytes) {
                    images[src] = decoded
                }
            }
        }
        title = doc.Title
        if let cb = onTitle { cb(title) }
        needsStyle = true
        needsRepaint = true
    }

    /// Adds a stylesheet: its rules, and the fonts its @font-face rules
    /// name, registered from the files they point at.
    func addSheet(_ sheet: css.StyleSheet, depth: int = 0) {
        // @import brings another sheet in first, as it precedes the rules.
        if depth < 8 {
            for at in sheet.AtRules where at.Name == "import" {
                let b = [uint8](at.Params.utf8)
                var url = ""
                var i = 0
                // The URL is the first string or url() in the params.
                if b.count > 4 && startsWithBytes(b, "url(") {
                    var j = 4
                    while j < b.count && (b[j] == 34 || b[j] == 39 || b[j] == 32) { j += 1 }
                    let start = j
                    while j < b.count && b[j] != 41 && b[j] != 34 && b[j] != 39 { j += 1 }
                    url = draw.stringOf(b, start, j)
                } else if !b.isEmpty && (b[0] == 34 || b[0] == 39) {
                    i = 1
                    while i < b.count && b[i] != b[0] { i += 1 }
                    url = draw.stringOf(b, 1, i)
                }
                if url.isEmpty { continue }
                if let bytes = loadResource(Resolve(url)) {
                    addSheet(css.Parse(draw.stringOf(bytes, 0, bytes.count)), depth: depth + 1)
                }
            }
        }
        resolver.Author.Add(sheet)
        for at in sheet.AtRules where at.Name == "font-face" {
            var family = ""
            var sources: [string] = []
            for d in at.Declarations {
                if d.Property == "font-family" {
                    for t in d.Tokens where t.Kind == .string || t.Kind == .ident {
                        family = family.isEmpty ? t.Value : family + " " + t.Value
                    }
                } else if d.Property == "src" {
                    for t in d.Tokens where t.Kind == .url { sources.append(t.Value) }
                }
            }
            if family.isEmpty { continue }
            for src in sources {
                var path = Resolve(src)
                if path.hasPrefix("file://") {
                    let b = [uint8](path.utf8)
                    path = draw.stringOf(b, 7, b.count)
                }
                if path.contains("://") { continue }
                if font.Register(path: path, as: family) {
                    fontFaces.append(family)
                    break
                }
            }
        }
    }

    /// A URL made absolute against the page's base: absolute ones and
    /// fragments are left alone.
    public func Resolve(_ url: string) -> string {
        if url.isEmpty { return baseURL }
        if url.hasPrefix("#") { return url }
        if url.contains("://") || url.hasPrefix("data:") || url.hasPrefix("/") || url.hasPrefix("about:") { return url }
        if baseURL.isEmpty { return url }
        if baseURL.hasSuffix("/") { return baseURL + url }
        return baseURL + "/" + url
    }

    func loadResource(_ url: string) -> [uint8]? {
        if let loader = Configuration.ResourceLoader {
            return loader(url)
        }
        var path = url
        if path.hasPrefix("file://") {
            let b = [uint8](path.utf8)
            path = draw.stringOf(b, 7, b.count)
        }
        if path.contains("://") { return nil }
        if let bytes = try? fs.ReadFile(fs.Path(path)) {
            return bytes
        }
        return nil
    }

    /// The page's title, from <title>.
    public var Title: string { return title }

    /// Adds an image the page may refer to by URL, as when the host
    /// fetches it; the page is laid out again with it.
    public func SetImage(_ url: string, _ image: draw.Image) {
        images[url] = image
        needsStyle = true
    }

    // MARK: - Geometry

    /// Where the view sits in the window, and how big it is, in points.
    public func SetBounds(origin: window.Point, size: window.Size) {
        let widthChanged = self.size.Width != size.Width
        let heightChanged = self.size.Height != size.Height
        self.origin = origin
        self.size = size
        if widthChanged || heightChanged {
            resolver.ViewportWidth = size.Width
            resolver.ViewportHeight = size.Height
            if resolver.Author.UsesViewport || resolver.UA.UsesViewport {
                needsStyle = true
            } else {
                needsLayout = true
            }
        }
        needsRepaint = true
    }

    public func Bounds() -> (origin: window.Point, size: window.Size) {
        return (origin: origin, size: size)
    }

    public func ScrollOffset() -> window.Point { return scroll }

    public func SetScrollOffset(_ offset: window.Point) {
        scroll = offset
        clampScroll()
        needsRepaint = true
    }

    /// The size of the whole page, in points.
    public func ContentSize() -> window.Size {
        update()
        return window.Size(contentWidth, contentHeight)
    }

    public func NeedsRepaint() -> bool { return needsRepaint || needsStyle || needsLayout || needsPaint }

    /// Whether the view has something moving on its own -- a blinking
    /// caret -- and wants frames while it does. A host that gets true
    /// calls `Advance` with each frame's time and keeps requesting frames.
    public func NeedsAnimation() -> bool {
        if let f = focused { return isTextControl(f) }
        return false
    }

    /// Moves the view's own animation to a time in seconds: the caret
    /// blinks at a second per cycle. Answers whether a repaint is needed.
    public func Advance(time: float64) -> bool {
        guard NeedsAnimation() else { return false }
        if caretPhase < 0 { caretPhase = time }
        let phase = time - caretPhase
        let cycles = phase - float64(int64(phase))
        let visible = cycles < 0.5
        if visible != caretVisible {
            caretVisible = visible
            needsPaint = true
            return true
        }
        return false
    }
    public func DesiredCursor() -> window.Cursor? { return cursor }

    // MARK: - Callbacks

    /// Called with the resolved URL when the user follows a link.
    public func OnNavigate(_ handler: (string) -> Void) { onNavigate = handler }
    /// Called when a form is submitted: by its button, or Enter in a field.
    public func OnSubmit(_ handler: (Submission) -> Void) { onSubmit = handler }
    /// Called when a button outside a form is pressed, with its name and value.
    public func OnAction(_ handler: (string, string) -> Void) { onAction = handler }
    public func OnTitleChanged(_ handler: (string) -> Void) { onTitle = handler }
    /// Called with a link's URL as the pointer moves onto it, and nil off it.
    public func OnHoverLink(_ handler: (string?) -> Void) { onHoverLink = handler }
    /// Asked whether a resolved URL has been visited, for `:visited`.
    /// Call `Invalidate()` when the answer changes.
    public func IsVisited(_ handler: (string) -> bool) { isVisited = handler; needsStyle = true }

    // MARK: - The pipeline

    /// Brings the page up to date: boxes, layout and the display list,
    /// whichever are stale.
    func update() {
        if needsStyle {
            builder.Images = images
            builder.Values = values
            context.Reset()
            context.Hovered = hovered
            context.Focused = focused
            context.Active = pressed
            if let v = isVisited, resolver.UsesVisited {
                context.Visited = { node in
                    if let href = node.GetAttribute("href") { return v(self.Resolve(href)) }
                    return false
                }
            } else {
                context.Visited = nil
            }
            if let doc = Document {
                root = builder.Build(doc)
            } else {
                root = nil
            }
            needsStyle = false
            needsLayout = true
        }
        if needsLayout {
            if let r = root {
                let layout = Layout(viewportWidth: size.Width, viewportHeight: size.Height)
                layout.Run(r)
                self.layout = layout
                contentHeight = r.Y + r.Height + r.Margin.Bottom
                contentWidth = r.X + r.Width + r.Margin.Right
                if r.ContentWidth + r.X + r.ContentX > contentWidth { contentWidth = r.ContentWidth + r.X + r.ContentX }
            } else {
                contentHeight = 0
                contentWidth = 0
            }
            clampScroll()
            needsLayout = false
            needsPaint = true
        }
        if needsPaint {
            if let r = root {
                let b = DisplayListBuilder()
                b.focused = focused?.Id ?? 0
                b.caret = caret
                b.caretVisible = caretVisible
                b.images = images
                if let range = selectionRange() {
                    b.selectionStart = range.start
                    b.selectionEnd = range.end
                    b.textOrder = builder.textOrder
                }
                displayList = b.build(r, viewportWidth: size.Width, viewportHeight: size.Height, background: Configuration.BackgroundColor)
            } else {
                displayList = []
            }
            needsPaint = false
            needsRepaint = true
        }
    }

    func clampScroll() {
        let maxY = contentHeight > size.Height ? contentHeight - size.Height : 0
        let maxX = contentWidth > size.Width ? contentWidth - size.Width : 0
        if scroll.Y > maxY { scroll.Y = maxY }
        if scroll.Y < 0 { scroll.Y = 0 }
        if scroll.X > maxX { scroll.X = maxX }
        if scroll.X < 0 { scroll.X = 0 }
        // Sticky boxes follow the scroll, which repaints them.
        if let l = layout, !l.Sticky.isEmpty {
            if l.UpdateSticky(scrollY: scroll.Y, viewportHeight: size.Height) {
                needsPaint = true
            }
        }
    }

    // MARK: - Drawing

    /// Paints the page into the window's pixels at the view's bounds.
    public func Draw(into pixels: inout [uint8], canvasSize: window.PixelSize, scale: float32) {
        update()
        let viewRect = draw.Rect(origin.X, origin.Y, size.Width, size.Height).Snapped(scale: scale)
        let list = displayList
        let sx = scroll.X
        let sy = scroll.Y
        let bg = Configuration.BackgroundColor
        let showBar = contentHeight > size.Height
        let barHeight = size.Height * size.Height / (contentHeight > 0 ? contentHeight : 1)
        let barY = size.Height > barHeight ? (size.Height - barHeight) * (sy / (contentHeight - size.Height)) : 0
        draw.WithCanvas(&pixels, width: canvasSize.Width, height: canvasSize.Height) { c in
            var canvas = c
            canvas.ClipTo(viewRect)
            if bg.A > 0 { canvas.Fill(viewRect, bg) }
            rasterize(list, on: canvas, scale: scale, originX: float32(viewRect.X), originY: float32(viewRect.Y), scrollX: sx, scrollY: sy)
            if showBar {
                let track = draw.Rect(origin.X + size.Width - 10, origin.Y + barY + 2, 6, barHeight - 4).Snapped(scale: scale)
                canvas.FillRounded(track, radii: draw.Radii(all: 3 * scale), draw.Color(0, 0, 0, 90))
            }
        }
        needsRepaint = false
    }

    // MARK: - Finding things

    /// The element under a point in the window, or nil.
    public func ElementAt(_ p: window.Point) -> html.Node? {
        update()
        return hitAt(p)?.Node
    }

    func hitAt(_ p: window.Point) -> Hit? {
        guard let r = root else { return nil }
        let px = p.X - origin.X + scroll.X
        let py = p.Y - origin.Y + scroll.Y
        return hitTest(r, px, py, originX: 0, originY: 0)
    }

    /// The layout box of an element, once laid out.
    public func BoxFor(_ node: html.Node) -> Box? {
        update()
        return builder.byNode[node.Id]
    }

    /// The root of the layout tree.
    public var RootBox: Box? {
        update()
        return root
    }

    public func QuerySelector(_ sel: string) -> html.Node? {
        guard let doc = Document else { return nil }
        return selector.QuerySelector(sel, in: doc.Root)
    }

    public func QuerySelectorAll(_ sel: string) -> [html.Node] {
        guard let doc = Document else { return [] }
        return selector.QuerySelectorAll(sel, in: doc.Root)
    }

    /// The element with keyboard focus.
    public var FocusedElement: html.Node? { return focused }

    /// The selection's ends in document order, or nil for none.
    func selectionRange() -> (start: TextPosition, end: TextPosition)? {
        guard let a = selectionAnchor, let f = selectionFocus else { return nil }
        let ao = builder.textOrder[a.Node.Id] ?? 0
        let fo = builder.textOrder[f.Node.Id] ?? 0
        if ao < fo || (ao == fo && a.Offset <= f.Offset) {
            if ao == fo && a.Offset == f.Offset { return nil }
            return (start: a, end: f)
        }
        return (start: f, end: a)
    }

    /// Whether any text is selected.
    public var HasSelection: bool { return selectionRange() != nil }

    /// The selected text, with a line break where the selection spans lines.
    public func SelectedText() -> string {
        update()
        guard let range = selectionRange(), let r = root else { return "" }
        var out = ""
        var pastLine = false
        collectSelectedText(r, range, &out, &pastLine)
        return out
    }

    func collectSelectedText(_ box: Box, _ range: (start: TextPosition, end: TextPosition), _ out: inout string, _ lineBroken: inout bool) {
        if box.Kind == .replaced { return }
        if !box.Lines.isEmpty {
            for line in box.Lines {
                var tookSomething = false
                for f in line.Fragments {
                    if f.Kind == .atomic {
                        collectSelectedText(f.Box, range, &out, &lineBroken)
                        continue
                    }
                    if f.Kind != .text { continue }
                    guard let node = f.Box.Node else { continue }
                    if let part = selectedPart(f, node, range, builder.textOrder) {
                        if lineBroken && !out.isEmpty { out += "\n" }
                        lineBroken = false
                        let bytes = [uint8](f.Text.utf8)
                        out += draw.stringOf(bytes, part.from, part.to)
                        tookSomething = true
                    }
                }
                if tookSomething { lineBroken = true }
            }
            return
        }
        for child in box.Children {
            if child.Kind == .text || child.Kind == .inline || child.Kind == .lineBreak { continue }
            collectSelectedText(child, range, &out, &lineBroken)
        }
    }

    /// Clears the selection.
    public func ClearSelection() {
        if selectionAnchor != nil || selectionFocus != nil {
            selectionAnchor = nil
            selectionFocus = nil
            needsPaint = true
        }
    }

    /// Selects all the text on the page.
    public func SelectAll() {
        update()
        guard let r = root else { return }
        var first: Box? = nil
        var last: Box? = nil
        findTextBoxes(r, &first, &last)
        guard let f = first, let l = last, let fn = f.Node, let ln = l.Node else { return }
        selectionAnchor = TextPosition(Node: fn, Offset: 0)
        selectionFocus = TextPosition(Node: ln, Offset: l.Text.utf8.count)
        needsPaint = true
    }

    /// Selects the text of the block a text box is in.
    func selectBlock(of text: Box) {
        var block: Box = text
        while let p = block.Parent, block.Kind != .block && block.Kind != .inlineBlock { block = p }
        var first: Box? = nil
        var last: Box? = nil
        findTextBoxes(block, &first, &last)
        guard let f = first, let l = last, let fn = f.Node, let ln = l.Node else { return }
        selectionAnchor = TextPosition(Node: fn, Offset: 0)
        selectionFocus = TextPosition(Node: ln, Offset: l.Text.utf8.count)
        needsPaint = true
    }

    func findTextBoxes(_ box: Box, _ first: inout Box?, _ last: inout Box?) {
        if box.Kind == .text {
            if !isBlank(box.Text) {
                if first == nil { first = box }
                last = box
            }
            return
        }
        for c in box.Children { findTextBoxes(c, &first, &last) }
    }

    /// Gives an element focus, as clicking it or tabbing to it would.
    public func Focus(_ node: html.Node?) {
        if focused?.Id == node?.Id { return }
        focused = node
        if let n = node {
            let value = valueOf(n)
            caret = value.utf8.count
        }
        showCaret()
        stateChanged()
        needsPaint = true
    }

    /// Hover, focus or the press moved: styles need recomputing only
    /// where a rule asking about them matches differently now, which
    /// the trace of the last build tells without a rebuild.
    func stateChanged() {
        if needsStyle || root == nil { return }
        if resolver.StateTrace.isEmpty { return }
        context.Hovered = hovered
        context.Focused = focused
        context.Active = pressed
        for e in resolver.StateTrace {
            let m = e.pseudo.isEmpty
                ? selector.MatchComplexIn(e.rule.Selector, e.node, context)
                : selector.MatchComplexIn(e.rule.Selector, e.node, context, pseudoElement: e.pseudo)
            if m != e.matched {
                needsStyle = true
                return
            }
        }
    }

    /// Scrolls so that an element is in view.
    public func ScrollTo(_ node: html.Node) {
        update()
        guard let b = builder.byNode[node.Id] else { return }
        let pos = pagePosition(b)
        scroll.Y = pos.y
        clampScroll()
        needsRepaint = true
    }

    /// Marks the page as changed: the host edited the DOM.
    public func Invalidate() {
        needsStyle = true
    }

    /// The text a form control holds now.
    public func ValueOf(_ node: html.Node) -> string {
        return valueOf(node)
    }

    func valueOf(_ node: html.Node) -> string {
        if let v = values[node.Id] { return v }
        if node.TagName == "textarea" { return node.InnerText() }
        return node.GetAttribute("value") ?? ""
    }

    func setValue(_ node: html.Node, _ value: string) {
        values[node.Id] = value
        showCaret()
        needsStyle = true
    }

    /// Shows the caret now, as typing or moving does, restarting its blink.
    func showCaret() {
        caretVisible = true
        caretPhase = -1
    }
}

func decodeImage(_ bytes: [uint8]) -> draw.Image? {
    return image.Decode(bytes)
}

func collectTags(_ node: html.Node, _ tag: string, _ out: inout [html.Node]) {
    for c in node.Children where c.Kind == html.NodeKind.element {
        if c.TagName == tag { out.append(c) }
        collectTags(c, tag, &out)
    }
}

func startsWithBytes(_ b: [uint8], _ prefix: string) -> bool {
    let p = [uint8](prefix.utf8)
    if b.count < p.count { return false }
    var i = 0
    while i < p.count {
        if b[i] != p[i] { return false }
        i += 1
    }
    return true
}
