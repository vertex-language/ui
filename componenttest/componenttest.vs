// Package componenttest tests .vsx components as a user meets them:
// mounted headless in a real page, found by role, label, text or
// placeholder, clicked and typed into through the page's own input, and
// looked at -- their computed styles, and their pixels against a golden
// image (proposed_vsx.md §11).
//
//     let screen = componenttest.Mount(width: 420, height: 600) { <App store={store} /> }
//     screen.Type(into: screen.ByPlaceholder("What needs doing?"), "buy milk")
//     screen.Press("Enter")
//     check(screen.ByRole("listitem").Count == 1, "adds one item")
//     screen.Click(screen.ByRole("checkbox"))
//     check(screen.Pixels().Matches(golden: "testdata/done.png"), "pixels")
//
// A query finds what an assistive technology would: an element's role is
// its `role` attribute or the one its tag implies (a button, a link, a
// checkbox, a list item, a heading), so a test that finds a control by
// role finds what VoiceOver will.
package componenttest

import (
    "fs"
    "image"
    "image/draw"
    "image/png"
    "reactive"
    "ui/component"
    "web"
    "web/cascade"
    "web/html"
)

/// A mounted component and the page it is in.
@MainActor
public final class Screen {
    public let Page: web.Page
    public let Mounted: component.Mounted
    let width: int32
    let height: int32

    init(page: web.Page, mounted: component.Mounted, width: int32, height: int32) {
        Page = page
        Mounted = mounted
        self.width = width
        self.height = height
    }

    // MARK: - Queries

    /// Elements whose role -- written, or the one their tag implies -- is
    /// role: "button", "link", "checkbox", "textbox", "listitem",
    /// "heading", "list", "img", "navigation", "main".
    public func ByRole(_ role: string) -> Found {
        return find { n in roleOf(n) == role }
    }

    /// Elements whose own text, whitespace collapsed, is text.
    public func ByText(_ text: string) -> Found {
        return find { n in collapse(n.InnerText()) == text && !n.Children.contains { c in c.Kind == html.NodeKind.element && collapse(c.InnerText()) == text } }
    }

    /// Controls labelled text: by aria-label, or by a <label> around them
    /// or pointing at them with `for`.
    public func ByLabel(_ text: string) -> Found {
        var ids: [string] = []
        var wrapped: [html.Node] = []
        for l in all() where l.TagName == "label" && collapse(l.InnerText()) == text {
            if let f = l.GetAttribute("for") { ids.append(f) }
            for c in descendants(l) where isControl(c) { wrapped.append(c) }
        }
        return find { n in
            n.GetAttribute("aria-label") == text || (n.IdAttr().map { ids.contains($0) } ?? false) ||
                wrapped.contains { w in w.Id == n.Id }
        }
    }

    public func ByPlaceholder(_ text: string) -> Found {
        return find { n in n.GetAttribute("placeholder") == text }
    }

    /// Elements marked `data-testid="id"`.
    public func ByTestId(_ id: string) -> Found {
        return find { n in n.GetAttribute("data-testid") == id }
    }

    /// Elements matching a CSS selector.
    public func Query(_ selector: string) -> Found {
        return Found(Page.QuerySelectorAll(selector), self)
    }

    func find(_ test: (html.Node) -> bool) -> Found {
        var out: [html.Node] = []
        for n in all() where test(n) { out.append(n) }
        return Found(out, self)
    }

    func all() -> [html.Node] {
        guard let doc = Page.Document else { return [] }
        return descendants(doc.Tree.Root)
    }

    // MARK: - Input

    /// Clicks the first element found, where the page hit-tests to it: a
    /// press and release, through the page's input, as a user's would.
    /// Answers whether there was somewhere to click.
    @discardableResult
    public func Click(_ found: Found) -> bool {
        guard let n = found.First, let p = pointOn(n) else { return false }
        reactive.Batch {
            _ = self.Page.Handle(.pointerDown(web.Pointer(p)))
            _ = self.Page.Handle(.pointerUp(web.Pointer(p)))
        }
        return true
    }

    /// Clicks a field to focus it, and types text into it.
    public func Type(into found: Found, _ text: string) {
        _ = Click(found)
        reactive.Batch { _ = self.Page.Handle(.text(text)) }
    }

    /// Presses a key where the focus is: "Enter", "Tab", "Backspace",
    /// "Escape", "ArrowDown", or a character.
    public func Press(_ key: string) {
        let code = key.count == 1 ? "Key" + key.uppercased() : key
        reactive.Batch { _ = self.Page.Handle(.keyDown(web.Key(Key: key, Code: code))) }
    }

    /// A point the page hit-tests to the element or something in it.
    func pointOn(_ n: html.Node) -> draw.Point? {
        render()
        var y: float32 = 1
        while y < float32(height) {
            var x: float32 = 1
            while x < float32(width) {
                let p = draw.Point(x, y)
                if let hit = Page.ElementAt(p), contains(n, hit) { return p }
                x += 3
            }
            y += 3
        }
        return nil
    }

    /// Shows the screen in a dark or a light color scheme, as the system's
    /// appearance would.
    public func SetDark(_ dark: bool) {
        Page.SetColorScheme(dark: dark)
    }

    // MARK: - Looking

    /// The screen's pixels, drawn at scale 1.
    public func Pixels() -> Pixels {
        var px = [uint8](repeating: 0, count: int(width) * int(height) * 4)
        Page.Draw(into: &px, width: width, height: height, scale: 1)
        return componenttest.Pixels(image: image.RGBA(width: int(width), height: int(height), pixels: px))
    }

    func render() {
        var px = [uint8](repeating: 0, count: int(width) * int(height) * 4)
        Page.Draw(into: &px, width: width, height: height, scale: 1)
    }
}

/// What a query found: none, one, or more elements.
@MainActor
public struct Found {
    public let Nodes: [html.Node]
    let screen: Screen

    init(_ nodes: [html.Node], _ screen: Screen) {
        Nodes = nodes
        self.screen = screen
    }

    public var Count: int { return Nodes.count }
    public var Exists: bool { return !Nodes.isEmpty }
    public var First: html.Node? { return Nodes.first }

    /// The first element's text, whitespace collapsed.
    public var Text: string { return Nodes.first.map { collapse($0.InnerText()) } ?? "" }

    /// The first element's value, for a field: what the user sees in it.
    public var Value: string { return Nodes.first.map { screen.Page.ValueOf($0) } ?? "" }

    /// The first element's attribute.
    public func Attribute(_ name: string) -> string? { return Nodes.first?.GetAttribute(name) }

    public func HasClass(_ name: string) -> bool { return Nodes.first?.HasClass(name) ?? false }

    /// The first element's computed style, as laid out now.
    public var Style: cascade.ComputedStyle? {
        guard let n = Nodes.first else { return nil }
        screen.render()
        return screen.Page.BoxFor(n)?.Style
    }
}

/// A screen's pixels.
public struct Pixels {
    public let Image: image.RGBA

    public init(image: image.RGBA) {
        Image = image
    }

    /// The color at a point.
    public func At(_ x: int, _ y: int) -> draw.Color {
        let i = (y * Image.Width + x) * 4
        return draw.Color(Image.Pixels[i], Image.Pixels[i + 1], Image.Pixels[i + 2], Image.Pixels[i + 3])
    }

    /// Whether the pixels are the golden image's. A golden that does not
    /// exist yet is written, and matches: the first run records what the
    /// screen looks like, and later runs hold it to that. Delete the file
    /// to record it again.
    public func Matches(golden path: string) -> bool {
        guard let bytes = try? fs.ReadFile(fs.Path(path)) else {
            try? fs.WriteFile(fs.Path(path), png.Encode(Image))
            return true
        }
        guard let want = try? png.Decode(bytes) else { return false }
        return want.Width == Image.Width && want.Height == Image.Height && want.Pixels == Image.Pixels
    }

    /// Writes the pixels as a PNG, to look at.
    public func Write(_ path: string) {
        try? fs.WriteFile(fs.Path(path), png.Encode(Image))
    }
}

/// Mounts root headless in a page of a size, with its packages' styles.
@MainActor
public func Mount(width: int32 = 800, height: int32 = 600, css: string = "", _ root: () -> component.Node) -> Screen {
    let page = web.Page()
    page.SetViewportSize(draw.Size(float32(width), float32(height)))
    page.LoadHTML("<!doctype html><html><head><style>html { font: 14px system-ui; } body { margin: 0; }" + css + "</style></head><body></body></html>")
    let doc = page.Document!
    let body = doc.Tree.ElementsByTagName("body").first!
    let mounted = component.Mount(root, into: doc, at: body, styles: { sheets in page.SetStyleSheets(sheets) })
    return Screen(page: page, mounted: mounted, width: width, height: height)
}

// MARK: - Roles

/// An element's role: its role attribute, or what its tag implies.
func roleOf(_ n: html.Node) -> string {
    if let r = n.GetAttribute("role"), !r.isEmpty { return r }
    switch n.TagName {
    case "button": return "button"
    case "a": return n.HasAttribute("href") ? "link" : ""
    case "input":
        switch (n.GetAttribute("type") ?? "text").lowercased() {
        case "checkbox": return "checkbox"
        case "radio": return "radio"
        case "button", "submit", "reset": return "button"
        case "range": return "slider"
        case "search": return "searchbox"
        default: return "textbox"
        }
    case "textarea": return "textbox"
    case "select": return "combobox"
    case "li": return "listitem"
    case "ul", "ol": return "list"
    case "h1", "h2", "h3", "h4", "h5", "h6": return "heading"
    case "img": return "img"
    case "nav": return "navigation"
    case "main": return "main"
    case "form": return "form"
    case "dialog": return "dialog"
    case "table": return "table"
    case "p": return "paragraph"
    default: return ""
    }
}

func isControl(_ n: html.Node) -> bool {
    return n.TagName == "input" || n.TagName == "textarea" || n.TagName == "select" || n.TagName == "button"
}

func descendants(_ n: html.Node) -> [html.Node] {
    var out: [html.Node] = []
    for c in n.Children where c.Kind == html.NodeKind.element {
        out.append(c)
        out += descendants(c)
    }
    return out
}

func contains(_ a: html.Node, _ b: html.Node) -> bool {
    var cur: html.Node? = b
    while let n = cur {
        if n.Id == a.Id { return true }
        cur = n.Parent
    }
    return false
}

/// Text with its runs of whitespace made one space, and trimmed.
func collapse(_ s: string) -> string {
    var out = ""
    var space = false
    for ch in s {
        if ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
            space = !out.isEmpty
        } else {
            if space { out += " " }
            space = false
            out.append(ch)
        }
    }
    return out
}
