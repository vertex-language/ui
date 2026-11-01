// Package component is what markup in a .vsx file lowers to, and what
// puts it in a document (docs/vsx.md in vsc).
//
//     <p className={on ? "x on" : "x"} onClick={setN(n + 1)}>Hi {name}</p>
//
// is checked and lowered as
//
//     component.Element("p", [
//         component.Attribute.Live("class", { on ? "x on" : "x" }),
//         component.Attribute.On("click", dom.MouseEvent.self, { _ in setN(n + 1) }),
//     ], ["Hi ", component.Live({ name })])
//
// and `<Counter start={5} />` as `component.Call("main.Counter", { Counter(start: 5) })`.
// Element, Fragment and Component make Nodes, a description; Mount makes
// them real and keeps them so: a component renders again when its state
// is set (useState) or its parent renders, and the new description is
// applied to what is in the document -- elements kept and patched, keyed
// rows moved, components keeping their hooks. What the markup wrote in
// braces is live besides: it follows the signals it read (an @Observable
// model's properties) by itself, without its component rendering again.
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
    /// Handlers called as an event comes down to its target (onClickCapture).
    var captureHandlers: [(string, (dom.Event) -> void)] = []
    var refs: [(html.Node?) -> void] = []
    /// The stylesheet of the package whose markup made the element.
    var sheet: Sheet? = nil
    public internal(set) var Children: [Node] = []
    /// A live region: the nodes it is, made again when what it read changes.
    var live: (() -> [Node])? = nil
    /// A component: its fiber, which renders it.
    var fiber: ComponentFiber? = nil

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
        if fiber != nil { return [self] }
        // A fragment is its children, unless it carries a sheet (Styled) or
        // a key, which the mount has to see.
        if Tag.isEmpty && !isText && live == nil && sheet == nil && key.isEmpty { return Children }
        return [self]
    }

    /// The node as HTML, as it is now: what RenderHTML writes for a report
    /// or an email.
    public func Html() -> string {
        if isText { return escapeText(Text) }
        if let fib = fiber { return fib.render().Html() }
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

/// DOM element type aliases for .vsx v2 markup.
public typealias HTMLElement = html.Node
public typealias HTMLInputElement = html.Node
public typealias HTMLButtonElement = html.Node
public typealias HTMLDivElement = html.Node
public typealias HTMLSpanElement = html.Node
public typealias HTMLFormElement = html.Node

/// A component's children: either passed as a Node or as a closure.
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

/// A component's call, `<Counter start={5} />`, lowered as
/// `component.Call("main.Counter", { Counter(start: 5) })`: rendered by a
/// fiber the mount keeps while the same component stays in its place,
/// inside the context values given where the call was written. type is
/// the component's identity: another component in that place next time
/// is a new one there.
public func Call(_ type: string, _ f: @escaping () -> Node) -> Node {
    let n = Node()
    n.fiber = ComponentFiber(type, capturedNode(f))
    return n
}

/// A keyed component's call, `<TabItem key={t.ID} … />`: among its
/// siblings, its fiber (its state, its elements) goes with its key.
public func Key<K>(_ key: K, _ type: string, _ f: @escaping () -> Node) -> Node {
    let n = Call(type, f)
    n.key = "\(key)"
    return n
}

/// `<Comp ref={el} />`: a ref on a component holds the first element it
/// renders while it is in the document.
public func ForwardRef<T>(_ ref: Ref<T>, _ node: Node) -> Node {
    node.refs.append({ n in ref.current = n as? T })
    return node
}

/// `<Comp ref={setEl} />`: a setter given the component's first element.
public func ForwardRef<T>(_ setter: SetState<T?>, _ node: Node) -> Node {
    node.refs.append({ n in setter(n as? T) })
    return node
}

/// `<Comp ref={el in …} />`: called with the component's first element
/// once it is in the document, and with nil when it goes.
public func ForwardRef(_ callback: @escaping (HTMLElement?) -> void, _ node: Node) -> Node {
    node.refs.append(callback)
    return node
}

// MARK: - Attributes

/// How an attribute is given.
public enum AttributeKind {
    case text(string, string)
    case flag(string, bool)
    case key(string)
    case handler(string, (dom.Event) -> void)
    case captureHandler(string, (dom.Event) -> void)
    case liveText(string, () -> string?)
    case spread([string: string])
    case sheet(Sheet)
    /// `ref={…}`: given the element when it is in the document, and nil
    /// when it goes.
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
    /// anything else its text.
    public static func Value<V>(_ name: string, _ value: V) -> Attribute {
        if let b = value as? bool { return Attribute(.flag(name, b)) }
        if let text = attributeText(value) { return Attribute(.text(name, text)) }
        return Attribute(.none)
    }

    /// `name={expr}`, live: the attribute follows the signals expr reads.
    /// A field is controlled by its handler: `value={draft}
    /// onInput={e in setDraft(e.Value)}`.
    public static func Live<V>(_ name: string, _ f: () -> V) -> Attribute {
        return Attribute(.liveText(name, { attributeText(f()) }))
    }

    /// `onX={…}`: a handler, given the event as the type it is.
    public static func On<E: dom.Event>(_ event: string, _ type: E.Type, _ handler: (E) -> void) -> Attribute {
        return Attribute(.handler(event, { e in
            if let typed = e as? E { handler(typed) }
        }))
    }

    /// `onXCapture={…}`: a handler called as the event comes down to its
    /// target, before the target's own handlers.
    public static func OnCapture<E: dom.Event>(_ event: string, _ type: E.Type, _ handler: (E) -> void) -> Attribute {
        return Attribute(.captureHandler(event, { e in
            if let typed = e as? E { handler(typed) }
        }))
    }

    /// `key={k}` on an intrinsic element.
    public static func Key<V>(_ key: V) -> Attribute {
        return Attribute(.key("\(key)"))
    }

    /// `ref={el}`: el, a `Ref<HTMLElement>` from useRef, holds the element
    /// while it is in the document.
    public static func Ref<T>(_ ref: Ref<T>) -> Attribute {
        return Attribute(.ref({ n in
            ref.current = n as? T
        }))
    }

    /// `ref={setEl}`: a state setter is given the element once it is in
    /// the document, and nil when it goes.
    public static func Ref<T>(_ setter: SetState<T?>) -> Attribute {
        return Attribute(.ref({ n in
            setter(n as? T)
        }))
    }

    /// `ref={el in …}`: called with the element once it is in the
    /// document, and with nil when it goes.
    public static func Ref(_ callback: @escaping (HTMLElement?) -> void) -> Attribute {
        return Attribute(.ref(callback))
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
        case .captureHandler(let event, let h):
            n.captureHandlers.append((event, h))
        case .liveText(let name, let f):
            n.liveAttrs.append((name, f))
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
/// own cascade layer and scoped to its elements (docs/vss.md in vsc). The
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
