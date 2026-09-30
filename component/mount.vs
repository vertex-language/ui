package component

import (
    "reactive"
    "web/dom"
    "web/html"
)

/// A root put into a document: its nodes are made once, as the children
/// of the element it was mounted at, and each live part keeps itself up
/// to date -- a live text its text, a live attribute its value, a live
/// region its nodes, a list its rows -- until the root is unmounted.
public final class Mounted {
    let doc: dom.Document
    let parent: html.Node
    let styles: (([string]) -> void)?
    /// What the root made: every binding, and every list's rows.
    let owner = reactive.Owner()
    var used: [Sheet] = []
    var given: [string] = []
    /// How many times the root has run: once.
    public internal(set) var Renders = 0
    /// How many times a live part has run, the first time included.
    public internal(set) var Updates = 0

    init(doc: dom.Document, parent: html.Node, styles: (([string]) -> void)?) {
        self.doc = doc
        self.parent = parent
        self.styles = styles
    }

    /// Disposes every binding, and takes the root's nodes out of the
    /// document.
    public func Unmount() {
        owner.Dispose()
        for c in parent.Children { remove(c) }
    }

    // MARK: - Making nodes real

    func build(_ n: Node, into parent: html.Node, before: html.Node?) {
        if n.isText {
            doc.InsertBefore(parent, doc.CreateTextNode(n.Text), before)
            return
        }
        if let f = n.live {
            region(f, into: parent, before: before)
            return
        }
        if let spec = n.list {
            list(spec, into: parent, before: before)
            return
        }
        if n.Tag.isEmpty {
            for c in n.Children { build(c, into: parent, before: before) }
            return
        }
        let el = doc.CreateElement(n.Tag)
        if let s = n.sheet { note(s) }
        for (name, value) in n.attrs { doc.SetAttribute(el, name, value) }
        // The class and style attributes, with their live parts: one
        // binding each, where anything in them is live.
        if n.liveClasses.isEmpty {
            if let c = n.classNow() { doc.SetAttribute(el, "class", c) }
        } else {
            bind { self.set(el, "class", n.classNow()) }
        }
        if n.liveStyles.isEmpty {
            if let st = n.styleNow() { doc.SetAttribute(el, "style", st) }
        } else {
            bind { self.set(el, "style", n.styleNow()) }
        }
        for (name, f) in n.liveAttrs {
            bind { self.set(el, name, f()) }
        }
        for (event, h) in n.handlers { _ = doc.AddEventListener(el, event, h) }
        for c in n.Children { build(c, into: el, before: nil) }
        doc.InsertBefore(parent, el, before)
    }

    /// A binding: an effect owned by what is being made, counted.
    func bind(_ f: () -> void) {
        _ = reactive.Effect {
            self.Updates += 1
            f()
        }
    }

    func set(_ el: html.Node, _ name: string, _ value: string?) {
        if let v = value {
            doc.SetAttribute(el, name, v)
        } else {
            doc.RemoveAttribute(el, name)
        }
    }

    /// A live region: its nodes between two markers, made again -- and
    /// what they made disposed -- when what it read changes. Text that
    /// stays text is changed in place.
    func region(_ f: () -> [Node], into parent: html.Node, before: html.Node?) {
        let start = doc.CreateTextNode("")
        let end = doc.CreateTextNode("")
        doc.InsertBefore(parent, start, before)
        doc.InsertBefore(parent, end, before)
        bind {
            let nodes = f()
            reactive.Untracked {
                guard let p = end.Parent else { return }
                let current = self.between(start, end)
                if nodes.count == 1 && nodes[0].isText && current.count == 1 && current[0].Kind == html.NodeKind.text {
                    if current[0].Text != nodes[0].Text { self.doc.SetText(current[0], nodes[0].Text) }
                    return
                }
                for c in current { self.remove(c) }
                for n in nodes { self.build(n, into: p, before: end) }
                self.giveSheets()
            }
        }
    }

    /// A keyed list: each key's row made once, under an owner of its own,
    /// kept and moved while its key is in the list, and disposed when it
    /// goes.
    func list(_ spec: ListSpec, into parent: html.Node, before: html.Node?) {
        let start = doc.CreateTextNode("")
        let end = doc.CreateTextNode("")
        doc.InsertBefore(parent, start, before)
        doc.InsertBefore(parent, end, before)
        let rows = RowTable()
        reactive.OnCleanup {
            for r in rows.rows { r.owner.Dispose() }
        }
        bind {
            let count = spec.count()
            reactive.Untracked {
                guard let p = end.Parent else { return }
                var keys: [int] = []
                var i = 0
                while i < count {
                    keys.append(spec.key(i))
                    i += 1
                }
                // Rows whose key is gone.
                var kept: [Row] = []
                for r in rows.rows {
                    if keys.contains(r.key) {
                        kept.append(r)
                    } else {
                        r.owner.Dispose()
                        for c in self.between(r.start, r.end) { self.remove(c) }
                        self.remove(r.start)
                        self.remove(r.end)
                        spec.drop(r.key)
                    }
                }
                // Each key's row, in order: kept and given its item, or
                // made; moved where it is out of place.
                var next: [Row] = []
                var cursor: html.Node = self.after(start) ?? end
                i = 0
                while i < keys.count {
                    let k = keys[i]
                    var row: Row? = nil
                    for r in kept where r.key == k { row = r }
                    if let r = row {
                        spec.update(i, k)
                        if r.start !== cursor {
                            for c in [r.start] + self.between(r.start, r.end) + [r.end] {
                                self.doc.InsertBefore(p, c, cursor)
                            }
                        } else {
                            cursor = self.after(r.end) ?? end
                        }
                        next.append(r)
                    } else {
                        let r = Row(key: k, start: self.doc.CreateTextNode(""), end: self.doc.CreateTextNode(""))
                        self.doc.InsertBefore(p, r.start, cursor)
                        self.doc.InsertBefore(p, r.end, cursor)
                        reactive.WithOwner(r.owner) {
                            let node = spec.make(i, k)
                            self.build(node, into: p, before: r.end)
                        }
                        next.append(r)
                    }
                    i += 1
                }
                rows.rows = next
                self.giveSheets()
            }
        }
    }

    /// The nodes strictly between two markers.
    func between(_ start: html.Node, _ end: html.Node) -> [html.Node] {
        guard let p = start.Parent else { return [] }
        var out: [html.Node] = []
        var inside = false
        for c in p.Children {
            if c === end { break }
            if inside { out.append(c) }
            if c === start { inside = true }
        }
        return out
    }

    func after(_ n: html.Node) -> html.Node? {
        guard let p = n.Parent else { return nil }
        var seen = false
        for c in p.Children {
            if seen { return c }
            if c === n { seen = true }
        }
        return nil
    }

    func remove(_ n: html.Node) {
        doc.RemoveEventListeners(within: n)
        if let p = n.Parent { doc.RemoveChild(p, n) }
    }

    // MARK: - Styles

    func note(_ s: Sheet) {
        for u in used where u === s { return }
        used.append(s)
    }

    /// Hands the page the sheets the made nodes carry, when they change.
    func giveSheets() {
        guard let give = styles else { return }
        let css = ordered(used).map { $0.CSS }
        if css != given {
            given = css
            give(css)
        }
    }
}

/// One row of a keyed list: its key, the markers around its nodes, and
/// the owner of what making it made.
final class Row {
    let key: int
    let start: html.Node
    let end: html.Node
    let owner = reactive.Owner()

    init(key: int, start: html.Node, end: html.Node) {
        self.key = key
        self.start = start
        self.end = end
    }
}

final class RowTable {
    var rows: [Row] = []
    init() {}
}

/// Puts what root makes into a document, as the children of parent. The
/// root runs once; its live parts keep themselves up to date. styles is
/// given the stylesheets the nodes' packages carry, in cascade order,
/// whenever they change: a page sets them (web.Page.SetStyleSheets).
public func Mount(_ root: () -> Node, into doc: dom.Document, at parent: html.Node, styles: (([string]) -> void)? = nil) -> Mounted {
    let m = Mounted(doc: doc, parent: parent, styles: styles)
    reactive.WithOwner(m.owner) {
        m.Renders += 1
        let nodes = reactive.Untracked { root().Nodes() }
        for n in nodes { m.build(n, into: parent, before: nil) }
    }
    m.giveSheets()
    return m
}
