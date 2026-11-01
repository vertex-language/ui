// Package component is what markup in a .vsx file lowers to, and what
// puts it in a document (proposed_vsx.md).
//
//     <p className={on ? "x on" : "x"} onClick={n += 1}>Hi {name}</p>
//
// is checked and lowered as
//
//     component.Element("p", [
//         component.Attribute.Live("class", { on ? "x on" : "x" }),
//         component.Attribute.On("click", dom.MouseEvent.self, { _ in n += 1 }),
//     ], ["Hi ", component.Live({ name })])
//
// Element and Fragment make Nodes, a description; Mount makes them real,
// once. What the markup wrote in braces -- `{name}`, `className={...}` -- is
// live: Mount runs it as its own effect, which updates its own text or
// attribute when a signal it read changes, and nothing else. Components
// run once, untracked (`Component`), so a component's body is never run
// again by a change it read; `@State` in it is made once.
package component

import (
    "ui/state"
    "web/dom"
    "web/html"
)

/// What an element, a text, a fragment, a live region or a keyed item is:
/// a description, which Mount makes real.
public final class Node: Renderable, ExpressibleByNilLiteral, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    public internal(set) var Tag: string = ""
    public internal(set) var Text: string = ""
    var isText = false
    var key: string = ""
    var attrs: [(string, string)] = []
    var classes: [string] = []
    var styles: [(string, string)] = []
    /// Live attributes: the value, or nil for none.
    var liveAttrs: [(string, () -> string?)] = []
    var handlers: [(string, (dom.Event) -> void)] = []
    var refs: [(html.Node?) -> void] = []
    /// The stylesheet of the package whose markup made the element.
    var sheet: Sheet? = nil
    public internal(set) var Children: [Node] = []
    /// A live region: the nodes it is, made again when what it read changes.
    var live: (() -> [Node])? = nil
    /// A keyed component's lazy builder.
    var makeKeyed: (() -> Node)? = nil

    public init() {}

    public convenience init(nilLiteral: ()) {
        self.init()
    }

    public convenience init(stringLiteral value: string) {
        self.init()
        self.isText = true
        self.Text = value
    }

    public convenience init(integerLiteral value: int) {
        self.init()
        self.isText = true
        self.Text = "\(value)"
    }

    public convenience init(floatLiteral value: float64) {
        self.init()
        self.isText = true
        self.Text = "\(value)"
    }

    public convenience init(booleanLiteral value: bool) {
        self.init()
    }

    public func Nodes() -> [Node] {
        // A fragment is its children, unless it carries a sheet (Styled) or
        // a keyed component builder, which the mount has to see.
        if Tag.isEmpty && !isText && live == nil && sheet == nil && makeKeyed == nil && key.isEmpty { return Children }
        return [self]
    }

    /// The node as HTML, as it is now: what RenderHTML writes for a report
    /// or an email.
    public func Html() -> string {
        if isText { return escapeText(Text) }
        if let mk = makeKeyed { return mk().Html() }
        if let f = live { return state.Untracked { f() }.map { $0.Html() }.joined() }
        if Tag.isEmpty { return Children.map { $0.Html() }.joined() }
        var s = "<" + Tag
        for (n, v) in attributesNow() { s += v.isEmpty && booleanAttribute(n) ? " \(n)" : " \(n)=\"\(escapeText(v))\"" }
        s += ">"
        if voidElement(Tag) { return s }
        for c in Children { s += c.Html() }
        return s + "</" + Tag + ">"
    }

    /// The element's attributes as they are now: its own, its live ones,
    /// then its classes and styles gathered.
    func attributesNow() -> [(string, string)] {
        var out = attrs
        var hasLiveClass = false
        var hasLiveStyle = false
        for (name, f) in liveAttrs {
            if name == "class" { hasLiveClass = true }
            if name == "style" { hasLiveStyle = true }
            if let v = state.Untracked({ f() }) { out.append((name, v)) }
        }
        if !hasLiveClass, let c = classNow() { out.append(("class", c)) }
        if !hasLiveStyle, let st = styleNow() { out.append(("style", st)) }
        return out
    }

    /// The static class attribute.
    func classNow() -> string? {
        return classes.isEmpty ? nil : classes.joined(separator: " ")
    }

    /// The static style attribute.
    func styleNow() -> string? {
        var parts: [string] = []
        for (p, v) in styles { parts.append(p.isEmpty ? v : "\(p): \(v)") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}

/// A node as HTML, for a static page: a report, an email.
public func RenderHTML(_ node: Node) -> string { return node.Html() }

public func renderToString(_ node: Node) -> string { return node.Html() }

/// What a child of an element may be: an element, text, a number, or an
/// array or optional of them. A Bool is nothing, so `{flag && …}` reads
/// as it does in JSX.
public protocol Renderable {
    func Nodes() -> [Node]
}

public func Text(_ s: string) -> Node {
    let n = Node()
    n.isText = true
    n.Text = s
    return n
}

extension string: Renderable { public func Nodes() -> [Node] { return [Text(self)] } }
extension int: Renderable { public func Nodes() -> [Node] { return [Text("\(self)")] } }
extension float64: Renderable { public func Nodes() -> [Node] { return [Text("\(self)")] } }
extension bool: Renderable { public func Nodes() -> [Node] { return [] } }
// @inlinable: a client specializes these for its own element types, so
// their bodies have to travel in this module's interface.
extension Array: Renderable where Element: Renderable {
    @inlinable public func Nodes() -> [Node] {
        var out: [Node] = []
        for x in self { out += x.Nodes() }
        return out
    }
}
extension Optional: Renderable where Wrapped: Renderable {
    @inlinable public func Nodes() -> [Node] {
        if let w = self { return w.Nodes() }
        return []
    }
}

/// What `ref={$el}` fills: the element, while it is in the document.
///
///     @state.State var field: Ref = nil
///     <input ref={$field} />
///
/// (A .vsx file need not import web/html for it, whose Node would be
/// taken for a component's Node.)
public typealias Ref = html.Node?

/// A component's children: made when the component asks, inside it, as
/// one fragment.
public typealias Children = () -> Node

// MARK: - Typed CSS Style

public struct CSSValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public var raw: string = ""
    public init(_ value: string) { self.raw = value }
    public init(_ value: int) { self.raw = "\(value)px" }
    public init(_ value: float64) { self.raw = "\(value)" }
    public init(_ value: CSSValue) { self.raw = value.raw }
    public init(stringLiteral value: string) { self.raw = value }
    public init(integerLiteral value: int) { self.raw = "\(value)px" }
    public init(floatLiteral value: float64) { self.raw = "\(value)" }
    public init(nilLiteral: ()) { self.raw = "" }
}

public struct Style {
    public var color: CSSValue = ""
    public var backgroundColor: CSSValue = ""
    public var background: CSSValue = ""
    public var display: CSSValue = ""
    public var position: CSSValue = ""
    public var top: CSSValue = ""
    public var right: CSSValue = ""
    public var bottom: CSSValue = ""
    public var left: CSSValue = ""
    public var width: CSSValue = ""
    public var height: CSSValue = ""
    public var minWidth: CSSValue = ""
    public var minHeight: CSSValue = ""
    public var maxWidth: CSSValue = ""
    public var maxHeight: CSSValue = ""
    public var margin: CSSValue = ""
    public var marginTop: CSSValue = ""
    public var marginRight: CSSValue = ""
    public var marginBottom: CSSValue = ""
    public var marginLeft: CSSValue = ""
    public var padding: CSSValue = ""
    public var paddingTop: CSSValue = ""
    public var paddingRight: CSSValue = ""
    public var paddingBottom: CSSValue = ""
    public var paddingLeft: CSSValue = ""
    public var flex: CSSValue = ""
    public var flexDirection: CSSValue = ""
    public var alignItems: CSSValue = ""
    public var justifyContent: CSSValue = ""
    public var gap: CSSValue = ""
    public var border: CSSValue = ""
    public var borderRadius: CSSValue = ""
    public var borderColor: CSSValue = ""
    public var fontSize: CSSValue = ""
    public var fontWeight: CSSValue = ""
    public var lineHeight: CSSValue = ""
    public var textAlign: CSSValue = ""
    public var textDecoration: CSSValue = ""
    public var opacity: CSSValue = ""
    public var overflow: CSSValue = ""
    public var cursor: CSSValue = ""
    public var zIndex: CSSValue = ""
    public var transform: CSSValue = ""
    public var transition: CSSValue = ""
    public var boxShadow: CSSValue = ""

    public init(
        color: CSSValue = "",
        backgroundColor: CSSValue = "",
        background: CSSValue = "",
        display: CSSValue = "",
        position: CSSValue = "",
        top: CSSValue = "",
        right: CSSValue = "",
        bottom: CSSValue = "",
        left: CSSValue = "",
        width: CSSValue = "",
        height: CSSValue = "",
        minWidth: CSSValue = "",
        minHeight: CSSValue = "",
        maxWidth: CSSValue = "",
        maxHeight: CSSValue = "",
        margin: CSSValue = "",
        marginTop: CSSValue = "",
        marginRight: CSSValue = "",
        marginBottom: CSSValue = "",
        marginLeft: CSSValue = "",
        padding: CSSValue = "",
        paddingTop: CSSValue = "",
        paddingRight: CSSValue = "",
        paddingBottom: CSSValue = "",
        paddingLeft: CSSValue = "",
        flex: CSSValue = "",
        flexDirection: CSSValue = "",
        alignItems: CSSValue = "",
        justifyContent: CSSValue = "",
        gap: CSSValue = "",
        border: CSSValue = "",
        borderRadius: CSSValue = "",
        borderColor: CSSValue = "",
        fontSize: CSSValue = "",
        fontWeight: CSSValue = "",
        lineHeight: CSSValue = "",
        textAlign: CSSValue = "",
        textDecoration: CSSValue = "",
        opacity: CSSValue = "",
        overflow: CSSValue = "",
        cursor: CSSValue = "",
        zIndex: CSSValue = "",
        transform: CSSValue = "",
        transition: CSSValue = "",
        boxShadow: CSSValue = ""
    ) {
        self.color = color
        self.backgroundColor = backgroundColor
        self.background = background
        self.display = display
        self.position = position
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
        self.width = width
        self.height = height
        self.minWidth = minWidth
        self.minHeight = minHeight
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.margin = margin
        self.marginTop = marginTop
        self.marginRight = marginRight
        self.marginBottom = marginBottom
        self.marginLeft = marginLeft
        self.padding = padding
        self.paddingTop = paddingTop
        self.paddingRight = paddingRight
        self.paddingBottom = paddingBottom
        self.paddingLeft = paddingLeft
        self.flex = flex
        self.flexDirection = flexDirection
        self.alignItems = alignItems
        self.justifyContent = justifyContent
        self.gap = gap
        self.border = border
        self.borderRadius = borderRadius
        self.borderColor = borderColor
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineHeight = lineHeight
        self.textAlign = textAlign
        self.textDecoration = textDecoration
        self.opacity = opacity
        self.overflow = overflow
        self.cursor = cursor
        self.zIndex = zIndex
        self.transform = transform
        self.transition = transition
        self.boxShadow = boxShadow
    }

    public func pairs() -> [(string, string)] {
        var out: [(string, string)] = []
        func add(_ k: string, _ v: CSSValue) {
            if !v.raw.isEmpty { out.append((k, v.raw)) }
        }
        add("color", color)
        add("background-color", backgroundColor)
        add("background", background)
        add("display", display)
        add("position", position)
        add("top", top)
        add("right", right)
        add("bottom", bottom)
        add("left", left)
        add("width", width)
        add("height", height)
        add("min-width", minWidth)
        add("min-height", minHeight)
        add("max-width", maxWidth)
        add("max-height", maxHeight)
        add("margin", margin)
        add("margin-top", marginTop)
        add("margin-right", marginRight)
        add("margin-bottom", marginBottom)
        add("margin-left", marginLeft)
        add("padding", padding)
        add("padding-top", paddingTop)
        add("padding-right", paddingRight)
        add("padding-bottom", paddingBottom)
        add("padding-left", paddingLeft)
        add("flex", flex)
        add("flex-direction", flexDirection)
        add("align-items", alignItems)
        add("justify-content", justifyContent)
        add("gap", gap)
        add("border", border)
        add("border-radius", borderRadius)
        add("border-color", borderColor)
        add("font-size", fontSize)
        add("font-weight", fontWeight)
        add("line-height", lineHeight)
        add("text-align", textAlign)
        add("text-decoration", textDecoration)
        add("opacity", opacity)
        add("overflow", overflow)
        add("cursor", cursor)
        add("z-index", zIndex)
        add("transform", transform)
        add("transition", transition)
        add("box-shadow", boxShadow)
        return out
    }

    public func cssText() -> string {
        var parts: [string] = []
        for (k, v) in pairs() { parts.append("\(k): \(v)") }
        return parts.joined(separator: "; ")
    }
}

public protocol Props {}
public struct EmptyProps: Props { public init() {} }
public struct EmptyState { public init() {} }

// MARK: - Live parts

/// `{expr}` among an element's children: a region Mount keeps equal to
/// what expr is, running it again -- and only it -- when a signal it read
/// changes.
public func Live<V: Renderable>(_ f: () -> V) -> Node {
    return liveNode({ f().Nodes() })
}

func liveNode(_ f: () -> [Node]) -> Node {
    let n = Node()
    n.live = captured(f)
    return n
}

/// A component's call, `<Card …/>`: run once, untracked, so a change to
/// what its body read does not run it again -- its own live parts follow
/// what they read.
public func Component<T>(_ f: () -> T) -> T {
    return state.Untracked(f)
}

/// A keyed component's call, `<TabItem key={t.ID} …/>`: built once per
/// key in a live list and kept while its key remains.
public func Key<K>(_ key: K, _ f: () -> Node) -> Node {
    return keyedNode("\(key)", f)
}

func keyedNode(_ key: string, _ f: () -> Node) -> Node {
    let n = Node()
    n.key = key
    n.makeKeyed = capturedNode({ state.Untracked(f) })
    return n
}

// MARK: - Attributes

/// How an attribute is given.
public enum AttributeKind {
    case text(string, string)
    case flag(string, bool)
    case key(string)
    case handler(string, (dom.Event) -> void)
    case liveText(string, () -> string?)
    /// An attribute bound both ways: its live value, and the event and
    /// handler that write what the user did back.
    case bound(string, () -> string?, string, (dom.Event) -> void)
    case spread([string: string])
    case sheet(Sheet)
    /// `ref={$el}`: given the element when it is made, and nil when it goes.
    case ref((html.Node?) -> void)
    case none
}

/// One attribute of an element, as markup writes it.
public struct Attribute {
    public let Kind: AttributeKind

    public init(_ kind: AttributeKind) { Kind = kind }

    /// `name="text"`.
    public static func Static(_ name: string, _ value: string) -> Attribute {
        return Attribute(.text(name, value))
    }

    /// `name={value}`, taken once: a Bool is the attribute's presence,
    /// anything else its text; a signal is bound both ways.
    public static func Value<V>(_ name: string, _ value: V) -> Attribute {
        // vsc does not yet prefer non-generic overloads, so a signal is
        // found here.
        if let bound = bound(name, value) { return bound }
        if let b = value as? bool { return Attribute(.flag(name, b)) }
        if let text = attributeText(value) { return Attribute(.text(name, text)) }
        return Attribute(.none)
    }

    /// `name={expr}`, live: the attribute follows expr. `value={$draft}`
    /// is bound both ways.
    public static func Live<V>(_ name: string, _ f: () -> V) -> Attribute {
        let first = state.Untracked(f)
        if let b = bound(name, first) { return b }
        return Attribute(.liveText(name, { attributeText(f()) }))
    }

    /// `onX={…}`: a handler, given the event as the type it is.
    public static func On<E: dom.Event>(_ event: string, _ type: E.Type, _ handler: (E) -> void) -> Attribute {
        return Attribute(.handler(event, { e in
            if let typed = e as? E { handler(typed) }
        }))
    }

    /// `key={k}` on an intrinsic element.
    public static func Key<V>(_ key: V) -> Attribute {
        return Attribute(.key("\(key)"))
    }

    /// `ref={$el}`: el, an `html.Node?` state, is the element while it
    /// is in the document, and nil once it is gone.
    public static func Ref<V>(_ ref: V) -> Attribute {
        if let s = ref as? state.Signal<html.Node?> {
            return Attribute(.ref({ n in
                var w = s
                w.Value = n
            }))
        }
        return Attribute(.none)
    }

    /// `{...attrs}`.
    public static func Spread(_ attrs: [string: string]) -> Attribute {
        return Attribute(.spread(attrs))
    }

    /// The package the element's markup is in, where that package has
    /// styles: the element is stamped `data-p="package"`, which scopes
    /// them, and carries the sheet to the page. The compiler adds it.
    public static func Package(_ sheet: Sheet) -> Attribute {
        return Attribute(.sheet(sheet))
    }
}

/// An attribute's text for a value: a Bool is presence ("" or none), a
/// Style or dictionary of styles is formatted as CSS declarations.
func attributeText<V>(_ v: V) -> string? {
    if let b = v as? bool { return b ? "" : nil }
    if let st = v as? Style {
        let s = st.cssText()
        return s.isEmpty ? nil : s
    }
    if let dict = v as? [string: string] {
        var parts: [string] = []
        for k in dict.keys.sorted() {
            let val = dict[k]!
            if !val.isEmpty { parts.append("\(k): \(val)") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
    return "\(v)"
}

/// A signal given to an attribute, bound both ways: text, a number (what
/// the user types is parsed back; what does not parse is left), or a
/// Boolean. Generic, so the casts are made where the signal's type is.
func bound<V>(_ name: string, _ value: V) -> Attribute? {
    if let s = value as? state.Signal<string> { return bindText(name, s) }
    if let s = value as? state.Signal<bool> { return bindFlag(name, s) }
    if let s = value as? state.Signal<int> {
        return bindParsed(name, { "\(s.Value)" }, { text in
            if let n = int(text) {
                var w = s
                w.Value = n
            }
        })
    }
    if let s = value as? state.Signal<float64> {
        return bindParsed(name, { "\(s.Value)" }, { text in
            if let x = float64(text) {
                var w = s
                w.Value = x
            }
        })
    }
    return nil
}

/// An attribute following read, whose input events hand what was typed to
/// write.
func bindParsed(_ name: string, _ read: () -> string, _ write: (string) -> void) -> Attribute {
    return Attribute(.bound(name, { read() }, "input", { e in
        if let i = e as? dom.InputEvent { write(i.Value) }
    }))
}

func bindText(_ name: string, _ signal: state.Signal<string>) -> Attribute {
    let s = signal
    return Attribute(.bound(name, { s.Value }, "input", { e in
        if let i = e as? dom.InputEvent {
            var w = s
            w.Value = i.Value
        }
    }))
}

func bindFlag(_ name: string, _ signal: state.Signal<bool>) -> Attribute {
    let s = signal
    return Attribute(.bound(name, { s.Value ? "" : nil }, "change", { e in
        // The page has toggled the box; the signal follows it.
        var w = s
        w.Value = !w.Peek()
    }))
}

/// An HTML element.
public func Element(_ tag: string, _ attributes: [Attribute], _ children: [any Renderable]) -> Node {
    let n = Node()
    n.Tag = tag
    for a in attributes {
        switch a.Kind {
        case .text(let name, let value):
            if name == "class" || name == "className" {
                if !value.isEmpty { n.classes.append(value) }
            } else if name == "style" {
                if !value.isEmpty { n.styles.append(("", value)) }
            } else {
                n.attrs.append((name, value))
            }
        case .flag(let name, let on):
            if on { n.attrs.append((name, "")) }
        case .key(let k):
            n.key = k
        case .handler(let event, let h):
            n.handlers.append((event, h))
        case .liveText(let name, let f):
            n.liveAttrs.append((name, f))
        case .bound(let name, let f, let event, let h):
            n.liveAttrs.append((name, f))
            n.handlers.append((event, h))
        case .spread(let attrs):
            for k in attrs.keys.sorted() {
                let v = attrs[k]!
                if k == "class" || k == "className" {
                    if !v.isEmpty { n.classes.append(v) }
                } else {
                    n.attrs.append((k, v))
                }
            }
        case .sheet(let sh):
            n.sheet = sh
            n.attrs.append(("data-p", sh.Package))
        case .ref(let give):
            n.refs.append(give)
        case .none:
            break
        }
    }
    for c in children { n.Children += c.Nodes() }
    return n
}

/// `<>…</>`: children with no element around them.
public func Fragment(_ children: [any Renderable]) -> Node {
    let n = Node()
    for c in children { n.Children += c.Nodes() }
    return n
}

public func Suspense(fallback: Node = nil, children: Node = nil) -> Node {
    return children
}

public func StrictMode(children: Node = nil) -> Node {
    return children
}

public func Profiler(id: string, onRender: ((string, string, float64) -> void)? = nil, children: Node = nil) -> Node {
    return children
}

/// content, carrying a package's sheet: what vsc wraps a component call in
/// when the package making the call has styles, so its sheet reaches the
/// page even where all it makes is another package's component (a
/// program whose root is a library's window, whose document rules would
/// otherwise never apply).
public func Styled(_ sheet: Sheet, _ content: any Renderable) -> Node {
    if let cn = content as? Node, !cn.key.isEmpty {
        cn.sheet = sheet
        return cn
    }
    let n = Node()
    n.sheet = sheet
    n.Children += content.Nodes()
    return n
}

// MARK: - HTML

func escapeText(_ s: string) -> string {
    var out = ""
    for ch in s {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}

func booleanAttribute(_ name: string) -> bool {
    switch name {
    case "checked", "disabled", "hidden", "autofocus", "readonly", "required", "selected", "multiple", "open":
        return true
    default:
        return false
    }
}

func voidElement(_ tag: string) -> bool {
    switch tag {
    case "input", "br", "img", "hr", "meta", "link", "col", "source", "track", "wbr", "area", "embed":
        return true
    default:
        return false
    }
}

// MARK: - Styles

/// A package's compiled stylesheet: its .vss files as one sheet, in its
/// own cascade layer and scoped to its elements (proposed_vsx.md). The
/// compiler generates one for each package with .vss files, as
/// `__vssSheet`, after the sheets of the styled packages it imports.
public final class Sheet {
    public let Package: string
    public let CSS: string
    /// The sheets of the styled packages this package imports, which come
    /// before it in the cascade.
    public let After: [Sheet]

    public init(package: string, css: string, after: [Sheet]) {
        Package = package
        CSS = css
        After = after
    }
}

/// A style token: a custom property a package registers with @property
/// in its .vss, which a program sets to theme it. The compiler generates
/// them as the package's `Tokens`: `kit.Tokens.Accent`.
public struct Token {
    /// The custom property: `--kit-accent`.
    public let Name: string
    /// What it holds, as @property says: `<color>`, `<length>`, `*`.
    public let Syntax: string

    public init(name: string, syntax: string) {
        Name = name
        Syntax = syntax
    }
}

/// Sheets in cascade order: each after what it imports, and package
/// main's last, so the program overrides what it builds on.
func ordered(_ used: [Sheet]) -> [Sheet] {
    var out: [Sheet] = []
    for s in used { place(s, &out) }
    var rest: [Sheet] = []
    var mains: [Sheet] = []
    for s in out {
        if s.Package == "main" { mains.append(s) } else { rest.append(s) }
    }
    return rest + mains
}


func place(_ s: Sheet, _ out: inout [Sheet]) {
    for o in out where o === s { return }
    for a in s.After { place(a, &out) }
    out.append(s)
}
