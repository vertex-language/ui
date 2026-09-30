// Package component is what markup in a .vsx file lowers to, and what
// puts it in a document (proposed_vsx.md §9.2, §10).
//
//     <p class="x" onClick={n += 1}>Hi {name}</p>
//
// is checked and lowered as
//
//     component.Element("p", [
//         component.Attribute.Static("class", "x"),
//         component.Attribute.On("click", dom.MouseEvent.self, { _ in n += 1 }),
//     ], ["Hi ", name])
//
// Element and Fragment make Nodes: a description of elements, text and
// handlers. Mount puts a root's nodes into a dom.Document, and runs the
// root again whenever a signal it read changes, patching the document in
// place -- an element stays the element it was, so focus, the caret and
// the scroll position stay too. That is the check form's runtime; the
// emit form (phase two) will bind each hole to its own signal instead.
package component

import (
    "reactive"
    "web/dom"
)

/// What an element, a text or a fragment is: a description, which Mount
/// makes real.
public final class Node: Renderable {
    public internal(set) var Tag: string = ""
    public internal(set) var Text: string = ""
    var isText = false
    var attrs: [(string, string)] = []
    var classes: [string] = []
    var styles: [(string, string)] = []
    var handlers: [(string, (dom.Event) -> void)] = []
    /// The stylesheet of the package whose markup made the element.
    var sheet: Sheet? = nil
    public internal(set) var Children: [Node] = []

    init() {}

    public func Nodes() -> [Node] {
        // A fragment is its children.
        if Tag.isEmpty && !isText { return Children }
        return [self]
    }

    /// The node as HTML: what RenderHTML writes for a report or an email.
    public func Html() -> string {
        if isText { return escapeText(Text) }
        if Tag.isEmpty { return Children.map { $0.Html() }.joined() }
        var s = "<" + Tag
        for (n, v) in attributes() { s += v.isEmpty && booleanAttribute(n) ? " \(n)" : " \(n)=\"\(escapeText(v))\"" }
        s += ">"
        if voidElement(Tag) { return s }
        for c in Children { s += c.Html() }
        return s + "</" + Tag + ">"
    }

    /// The attributes the element is written with: its own, then its
    /// classes and styles gathered.
    func attributes() -> [(string, string)] {
        var out = attrs
        if !classes.isEmpty { out.append(("class", classes.joined(separator: " "))) }
        if !styles.isEmpty {
            out.append(("style", styles.map { $0.0.isEmpty ? $0.1 : "\($0.0): \($0.1)" }.joined(separator: "; ")))
        }
        return out
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

/// How an attribute is given.
public enum AttributeKind {
    case text(string, string)
    case flag(string, bool)
    case classFlag(string, bool)
    case style(string, string)
    case handler(string, (dom.Event) -> void)
    /// An attribute bound both ways: its value, and the event and handler
    /// that write what the user did back.
    case bound(string, string, bool, string, (dom.Event) -> void)
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

    /// `name={value}`: a Bool is the attribute's presence, anything else
    /// its text.
    public static func Value<V>(_ name: string, _ value: V) -> Attribute {
        // vsc does not yet prefer the non-generic overloads below for a
        // signal, so a signal is found here too.
        if let s = value as? reactive.Signal<string> { return bindText(name, s) }
        if let s = value as? reactive.Signal<bool> { return bindFlag(name, s) }
        if let b = value as? bool { return Attribute(.flag(name, b)) }
        return Attribute(.text(name, "\(value)"))
    }

    /// `name={$signal}`: bound both ways. The attribute follows the
    /// signal, and what the user types or checks is written back.
    public static func Value(_ name: string, _ signal: reactive.Signal<string>) -> Attribute {
        return bindText(name, signal)
    }

    public static func Value(_ name: string, _ signal: reactive.Signal<bool>) -> Attribute {
        return bindFlag(name, signal)
    }

    /// `onX={…}`: a handler, given the event as the type it is.
    public static func On<E: dom.Event>(_ event: string, _ type: E.Type, _ handler: (E) -> void) -> Attribute {
        return Attribute(.handler(event, { e in
            if let typed = e as? E { handler(typed) }
        }))
    }

    /// `class:name={on}`.
    public static func Class(_ name: string, _ on: bool) -> Attribute {
        return Attribute(.classFlag(name, on))
    }

    /// `style:property={value}`.
    public static func Style<V>(_ property: string, _ value: V) -> Attribute {
        return Attribute(.style(property, "\(value)"))
    }

    /// `ref={$el}`. Kept for the emit form; the check form sets nothing.
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

func bindText(_ name: string, _ signal: reactive.Signal<string>) -> Attribute {
    var s = signal
    return Attribute(.bound(name, s.Value, true, "input", { e in
        if let i = e as? dom.InputEvent {
            var w = signal
            w.Value = i.Value
        }
    }))
}

func bindFlag(_ name: string, _ signal: reactive.Signal<bool>) -> Attribute {
    var s = signal
    return Attribute(.bound(name, "", s.Value, "change", { e in
        // The page has toggled the box; the signal follows it.
        var w = signal
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
        case .bound(let name, let text, let on, let event, let h):
            if name == "value" {
                n.attrs.append((name, text))
            } else if on {
                n.attrs.append((name, ""))
            }
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

/// The keyed list (proposed_vsx.md §5.4). The check form renders each
/// item; the key is checked for its type and used by the emit form.
public func For<T>(each: [T], key: ((T) -> int)? = nil, children: (T) -> Node) -> Node {
    var kids: [Node] = []
    for item in each { kids.append(children(item)) }
    return fragmentOf(kids)
}

func fragmentOf(_ kids: [Node]) -> Node {
    let n = Node()
    for k in kids { n.Children += k.Nodes() }
    return n
}

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

/// The sheets a tree of nodes uses, in cascade order: each after what it
/// imports, and package main's last, so the program overrides what it
/// builds on.
public func SheetsOf(_ nodes: [Node]) -> [Sheet] {
    var used: [Sheet] = []
    for n in nodes { collectSheets(n, &used) }
    var ordered: [Sheet] = []
    var mains: [Sheet] = []
    for s in used { place(s, &ordered) }
    var rest: [Sheet] = []
    for s in ordered {
        if s.Package == "main" { mains.append(s) } else { rest.append(s) }
    }
    return rest + mains
}

func collectSheets(_ n: Node, _ used: inout [Sheet]) {
    if let s = n.sheet {
        var seen = false
        for u in used where u === s { seen = true }
        if !seen { used.append(s) }
    }
    for c in n.Children { collectSheets(c, &used) }
}

func place(_ s: Sheet, _ ordered: inout [Sheet]) {
    for o in ordered where o === s { return }
    for a in s.After { place(a, &ordered) }
    ordered.append(s)
}
