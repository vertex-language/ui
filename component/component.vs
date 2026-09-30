// Package component is what markup in a .vsx file lowers to, and what
// puts it in a document (proposed_vsx.md §9.2, §10).
//
//     <p class="x" class:on={on} onClick={n += 1}>Hi {name}</p>
//
// is checked and lowered as
//
//     component.Element("p", [
//         component.Attribute.Static("class", "x"),
//         component.Attribute.LiveClass("on") { on },
//         component.Attribute.On("click", dom.MouseEvent.self, { _ in n += 1 }),
//     ], ["Hi ", component.Live { name }])
//
// Element and Fragment make Nodes, a description; Mount makes them real,
// once. What the markup wrote in braces -- `{name}`, `class:on={on}` -- is
// live: Mount runs it as its own effect, which updates its own text or
// attribute when a signal it read changes, and nothing else. Components
// run once, untracked (`Component`), so a component's body is never run
// again by a change it read; `@State` in it is made once.
package component

import (
    "ui/state"
    "web/dom"
)

/// What an element, a text, a fragment, a live region or a keyed list is:
/// a description, which Mount makes real.
public final class Node: Renderable {
    public internal(set) var Tag: string = ""
    public internal(set) var Text: string = ""
    var isText = false
    var attrs: [(string, string)] = []
    var classes: [string] = []
    var styles: [(string, string)] = []
    /// Live attributes: the value, or nil for none.
    var liveAttrs: [(string, () -> string?)] = []
    var liveClasses: [(string, () -> bool)] = []
    var liveStyles: [(string, () -> string)] = []
    var handlers: [(string, (dom.Event) -> void)] = []
    /// The stylesheet of the package whose markup made the element.
    var sheet: Sheet? = nil
    public internal(set) var Children: [Node] = []
    /// A live region: the nodes it is, made again when what it read changes.
    var live: (() -> [Node])? = nil
    /// A keyed list (For).
    var list: ListSpec? = nil

    init() {}

    public func Nodes() -> [Node] {
        // A fragment is its children.
        if Tag.isEmpty && !isText && live == nil && list == nil { return Children }
        return [self]
    }

    /// The node as HTML, as it is now: what RenderHTML writes for a report
    /// or an email.
    public func Html() -> string {
        if isText { return escapeText(Text) }
        if let f = live { return state.Untracked { f() }.map { $0.Html() }.joined() }
        if let l = list { return l.snapshot().map { $0.Html() }.joined() }
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
        for (name, f) in liveAttrs {
            if let v = state.Untracked({ f() }) { out.append((name, v)) }
        }
        if let c = classNow() { out.append(("class", c)) }
        if let st = styleNow() { out.append(("style", st)) }
        return out
    }

    /// The class attribute: the static classes, and the live ones on.
    func classNow() -> string? {
        var names = classes
        for (name, on) in liveClasses where on() { names.append(name) }
        return names.isEmpty ? nil : names.joined(separator: " ")
    }

    /// The style attribute: the static declarations, then the live ones.
    func styleNow() -> string? {
        var parts: [string] = []
        for (p, v) in styles { parts.append(p.isEmpty ? v : "\(p): \(v)") }
        for (p, f) in liveStyles { parts.append("\(p): \(f())") }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }
}

/// A node as HTML, for a static page: a report, an email.
public func RenderHTML(_ node: Node) -> string { return node.Html() }

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
extension Array: Renderable where Element: Renderable {
    public func Nodes() -> [Node] {
        var out: [Node] = []
        for x in self { out += x.Nodes() }
        return out
    }
}
extension Optional: Renderable where Wrapped: Renderable {
    public func Nodes() -> [Node] {
        if let w = self { return w.Nodes() }
        return []
    }
}

/// A component's children: made when the component asks, inside it, as
/// one fragment.
public typealias Children = () -> Node

// MARK: - Live parts

/// `{expr}` among an element's children: a region Mount keeps equal to
/// what expr is, running it again -- and only it -- when a signal it read
/// changes.
public func Live<V: Renderable>(_ f: () -> V) -> Node {
    return liveNode({ f().Nodes() })
}

func liveNode(_ f: () -> [Node]) -> Node {
    let n = Node()
    n.live = f
    return n
}

/// A component's call, `<Card …/>`: run once, untracked, so a change to
/// what its body read does not run it again -- its own live parts follow
/// what they read.
public func Component<T>(_ f: () -> T) -> T {
    return state.Untracked(f)
}

// MARK: - Attributes

/// How an attribute is given.
public enum AttributeKind {
    case text(string, string)
    case flag(string, bool)
    case classFlag(string, bool)
    case style(string, string)
    case handler(string, (dom.Event) -> void)
    case liveText(string, () -> string?)
    case liveClass(string, () -> bool)
    case liveStyle(string, () -> string)
    /// An attribute bound both ways: its live value, and the event and
    /// handler that write what the user did back.
    case bound(string, () -> string?, string, (dom.Event) -> void)
    case spread([string: string])
    case sheet(Sheet)
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
        if let s = value as? state.Signal<string> { return bindText(name, s) }
        if let s = value as? state.Signal<bool> { return bindFlag(name, s) }
        if let b = value as? bool { return Attribute(.flag(name, b)) }
        return Attribute(.text(name, "\(value)"))
    }

    /// `name={expr}`, live: the attribute follows expr. `value={$draft}`
    /// is bound both ways.
    public static func Live<V>(_ name: string, _ f: () -> V) -> Attribute {
        let first = state.Untracked(f)
        if let s = first as? state.Signal<string> { return bindText(name, s) }
        if let s = first as? state.Signal<bool> { return bindFlag(name, s) }
        return Attribute(.liveText(name, { attributeText(f()) }))
    }

    /// `onX={…}`: a handler, given the event as the type it is.
    public static func On<E: dom.Event>(_ event: string, _ type: E.Type, _ handler: (E) -> void) -> Attribute {
        return Attribute(.handler(event, { e in
            if let typed = e as? E { handler(typed) }
        }))
    }

    /// `class:name={on}`, taken once.
    public static func Class(_ name: string, _ on: bool) -> Attribute {
        return Attribute(.classFlag(name, on))
    }

    /// `class:name={on}`, live.
    public static func LiveClass(_ name: string, _ on: () -> bool) -> Attribute {
        return Attribute(.liveClass(name, on))
    }

    /// `style:property={value}`, taken once.
    public static func Style<V>(_ property: string, _ value: V) -> Attribute {
        return Attribute(.style(property, "\(value)"))
    }

    /// `style:property={value}`, live.
    public static func LiveStyle<V>(_ property: string, _ f: () -> V) -> Attribute {
        return Attribute(.liveStyle(property, { "\(f())" }))
    }

    /// `ref={$el}`. Kept for the emit form's templates; nothing is set.
    public static func Ref<V>(_ ref: V) -> Attribute {
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

/// An attribute's text for a value: a Bool is presence ("" or none).
func attributeText<V>(_ v: V) -> string? {
    if let b = v as? bool { return b ? "" : nil }
    return "\(v)"
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
            if name == "class" {
                n.classes.append(value)
            } else if name == "style" {
                n.styles.append(("", value))
            } else {
                n.attrs.append((name, value))
            }
        case .flag(let name, let on):
            if on { n.attrs.append((name, "")) }
        case .classFlag(let name, let on):
            if on { n.classes.append(name) }
        case .style(let property, let value):
            n.styles.append((property, value))
        case .handler(let event, let h):
            n.handlers.append((event, h))
        case .liveText(let name, let f):
            n.liveAttrs.append((name, f))
        case .liveClass(let name, let f):
            n.liveClasses.append((name, f))
        case .liveStyle(let property, let f):
            n.liveStyles.append((property, f))
        case .bound(let name, let f, let event, let h):
            n.liveAttrs.append((name, f))
            n.handlers.append((event, h))
        case .spread(let attrs):
            for k in attrs.keys.sorted() { n.attrs.append((k, attrs[k]!)) }
        case .sheet(let sh):
            n.sheet = sh
            n.attrs.append(("data-p", sh.Package))
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

// MARK: - For

/// The keyed list (proposed_vsx.md §5.4): each item's row is made once,
/// and kept -- with its elements, their focus and their state -- as long
/// as its key is in the list, moved where the key moves. A row is given
/// its item as a Readable, which follows the item when it changes under
/// the same key. Without a key, an item's index is its key.
public func For<T>(each: () -> [T], key: ((T) -> int)? = nil, children: (state.Readable<T>) -> Node) -> Node {
    var items: [T] = []
    var cells: [int: state.Signal<T>] = [:]
    // Made by a non-generic function: vsc cannot yet reach an internal
    // class's metadata from generic code specialized in another module.
    return listNode(
        count: {
            items = each()
            return items.count
        },
        key: { i in
            if let k = key { return k(items[i]) }
            return i
        },
        make: { i, k in
            let cell = state.Signal<T>(items[i])
            cells[k] = cell
            return children(state.Readable(cell))
        },
        update: { i, k in
            if var c = cells[k] { c.Value = items[i] }
        },
        drop: { k in cells[k] = nil })
}

func listNode(count: () -> int, key: (int) -> int, make: (int, int) -> Node, update: (int, int) -> void, drop: (int) -> void) -> Node {
    let n = Node()
    n.list = ListSpec(count: count, key: key, make: make, update: update, drop: drop)
    return n
}

/// A keyed list, with its item type erased: what Mount needs of For.
final class ListSpec {
    /// Reads the items (followed) and answers how many there are.
    let count: () -> int
    /// The key of the item at an index of the last read.
    let key: (int) -> int
    /// Makes the row of the item at an index, under its key.
    let make: (int, int) -> Node
    /// Gives the row under a key the item now at an index.
    let update: (int, int) -> void
    /// Forgets the row under a key.
    let drop: (int) -> void

    init(count: () -> int, key: (int) -> int, make: (int, int) -> Node, update: (int, int) -> void, drop: (int) -> void) {
        self.count = count
        self.key = key
        self.make = make
        self.update = update
        self.drop = drop
    }

    /// Each item's row, made fresh: for RenderHTML.
    func snapshot() -> [Node] {
        var out: [Node] = []
        state.Untracked {
            let n = self.count()
            var i = 0
            while i < n {
                out += self.make(i, self.key(i)).Nodes()
                i += 1
            }
        }
        return out
    }
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
/// own cascade layer and scoped to its elements (proposed_vsx.md §7). The
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
