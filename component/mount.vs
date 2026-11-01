package component

import (
    "image/draw"
    "ui/state"
    "web/dom"
    "web/html"
)

/// A root put into a document: its nodes are made once, as the children
/// of the element it was mounted at, and each live part keeps itself up
/// to date -- a live text its text, a live attribute its value, a live
/// region its nodes, a keyed list its rows -- until the root is unmounted.
public final class Mounted {
    let doc: dom.Document
    let parent: html.Node
    let styles: (([string]) -> void)?
    let focus: ((html.Node?) -> void)?
    let measure: ((html.Node) -> draw.Rect?)?
    /// What the root made: every binding, and every keyed list's rows.
    let owner = state.Owner()
    var used: [Sheet] = []
    var given: [string] = []
    /// How many times the root has run: once.
    public internal(set) var Renders = 0
    /// How many times a live part has run, the first time included.
    public internal(set) var Updates = 0

    init(doc: dom.Document, parent: html.Node, styles: (([string]) -> void)?, focus: ((html.Node?) -> void)?, measure: ((html.Node) -> draw.Rect?)?) {
        self.doc = doc
        self.parent = parent
        self.styles = styles
        self.focus = focus
        self.measure = measure
    }

    /// Disposes every binding, and takes the root's nodes out of the
    /// document.
    public func Unmount() {
        owner.Dispose()
        for c in parent.Children { remove(c) }
    }

    // MARK: - Making nodes real

    func build(_ n: Node, into parent: html.Node, before: html.Node?) {
        buildDepth += 1
        defer { buildDepth -= 1 }
        if n.isText {
            doc.InsertBefore(parent, doc.CreateTextNode(n.Text), before)
            return
        }
        if let mk = n.makeKeyed {
            if let s = n.sheet { note(s) }
            for c in mk().Nodes() { build(c, into: parent, before: before) }
            return
        }
        if let f = n.live {
            region(f, into: parent, before: before)
            return
        }
        if n.Tag.isEmpty {
            if let s = n.sheet { note(s) }
            for c in n.Children { build(c, into: parent, before: before) }
            return
        }
        let el = doc.CreateElement(n.Tag)
        populateElement(n, el, into: parent, before: before)
    }

    func populateElement(_ n: Node, _ el: html.Node, into parent: html.Node, before: html.Node?) {
        if let s = n.sheet { note(s) }
        for (name, value) in n.attrs { doc.SetAttribute(el, name, value) }
        if let c = n.classNow() { doc.SetAttribute(el, "class", c) }
        if let st = n.styleNow() { doc.SetAttribute(el, "style", st) }
        for (name, f) in n.liveAttrs {
            bind { self.set(el, name, f()) }
        }
        for (event, h) in n.handlers {
            _ = doc.AddEventListener(el, event, { e in self.hosting { h(e) } })
        }
        for c in n.Children { build(c, into: el, before: nil) }
        doc.InsertBefore(parent, el, before)
        for give in n.refs {
            give(el)
            state.OnCleanup { give(nil) }
        }
        for (name, _) in n.attrs where name == "autofocus" {
            let me = self
            toMount.append({ me.focus?(el) })
            break
        }
    }

    func patchElement(_ n: Node, _ el: html.Node, owner: state.Owner) {
        buildDepth += 1
        defer { buildDepth -= 1 }
        owner.Dispose()
        doc.RemoveEventListeners(within: el)
        state.WithOwner(owner) {
            self.patchElementInOwner(n, el)
        }
    }

    func patchElementInOwner(_ n: Node, _ el: html.Node) {
        if let s = n.sheet { self.note(s) }
        var oldAttrs: [string] = []
        for a in el.Attributes { oldAttrs.append(a.Name) }
        for name in oldAttrs { self.doc.RemoveAttribute(el, name) }
        for (name, value) in n.attrs { self.doc.SetAttribute(el, name, value) }
        if let c = n.classNow() { self.doc.SetAttribute(el, "class", c) }
        if let st = n.styleNow() { self.doc.SetAttribute(el, "style", st) }
        for (name, f) in n.liveAttrs {
            self.bind { self.set(el, name, f()) }
        }
        for (event, h) in n.handlers {
            _ = self.doc.AddEventListener(el, event, { e in self.hosting { h(e) } })
        }
        if self.canPatchChildrenInPlace(n.Children, el.Children) {
            var i = 0
            while i < n.Children.count {
                let nc = n.Children[i]
                let oc = el.Children[i]
                if nc.isText {
                    if oc.Text != nc.Text { self.doc.SetText(oc, nc.Text) }
                } else {
                    self.patchElementInOwner(nc, oc)
                }
                i += 1
            }
        } else {
            for c in el.Children { self.remove(c) }
            for c in n.Children { self.build(c, into: el, before: nil) }
        }
        for give in n.refs {
            give(el)
            state.OnCleanup { give(nil) }
        }
    }

    func canPatchChildrenInPlace(_ next: [Node], _ curr: [html.Node]) -> bool {
        if next.count != curr.count { return false }
        var i = 0
        while i < next.count {
            let nc = next[i]
            let oc = curr[i]
            if nc.live != nil || nc.makeKeyed != nil {
                return false
            }
            if nc.isText {
                if oc.Kind != html.NodeKind.text { return false }
            } else if nc.Tag.isEmpty {
                return false
            } else {
                if oc.Kind != html.NodeKind.element || oc.TagName != nc.Tag { return false }
            }
            i += 1
        }
        return true
    }

    /// Runs body as this root's code: what it calls Focus on is focused
    /// in this root's page.
    func hosting(_ body: () -> void) {
        let prev = host
        host = self
        body()
        host = prev
    }

    /// A binding: an effect owned by what is being made, counted.
    func bind(_ f: () -> void) {
        _ = state.Effect {
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
    /// stays text is changed in place; keyed elements (`key={...}`) are
    /// reconciled by key.
    func region(_ f: () -> [Node], into parent: html.Node, before: html.Node?) {
        let start = doc.CreateTextNode("")
        let end = doc.CreateTextNode("")
        doc.InsertBefore(parent, start, before)
        doc.InsertBefore(parent, end, before)
        let rows = RowTable()
        state.OnCleanup {
            for r in rows.rows { r.owner.Dispose() }
        }
        bind {
            let nodes = f()
            state.Untracked {
                guard let p = end.Parent else { return }
                let hasKeys = !nodes.isEmpty && nodes.allSatisfy { !$0.key.isEmpty }
                if hasKeys || (!rows.rows.isEmpty && nodes.isEmpty) {
                    self.reconcileKeyed(nodes, rows: rows, in: p, start: start, end: end)
                    return
                }
                for r in rows.rows { r.owner.Dispose() }
                rows.rows = []
                let current = self.between(start, end)
                if nodes.count == 1 && nodes[0].isText && current.count == 1 && current[0].Kind == html.NodeKind.text {
                    if current[0].Text != nodes[0].Text { self.doc.SetText(current[0], nodes[0].Text) }
                    return
                }
                for c in current { self.remove(c) }
                for n in nodes { self.build(n, into: p, before: end) }
                self.giveSheets()
                self.hosting { runMounted() }
            }
        }
    }

    func reconcileKeyed(_ nodes: [Node], rows: RowTable, in p: html.Node, start: html.Node, end: html.Node) {
        var keys: [string] = []
        for n in nodes { keys.append(n.key) }
        var kept: [Row] = []
        for r in rows.rows {
            if keys.contains(r.key) {
                kept.append(r)
            } else {
                r.owner.Dispose()
                for c in self.between(r.start, r.end) { self.remove(c) }
                self.remove(r.start)
                self.remove(r.end)
            }
        }
        var next: [Row] = []
        var cursor: html.Node = self.after(start) ?? end
        var i = 0
        while i < nodes.count {
            let n = nodes[i]
            let k = n.key
            var row: Row? = nil
            for r in kept where r.key == k { row = r }
            if let r = row {
                if r.start !== cursor {
                    for c in [r.start] + self.between(r.start, r.end) + [r.end] {
                        self.doc.InsertBefore(p, c, cursor)
                    }
                } else {
                    cursor = self.after(r.end) ?? end
                }
                if n.makeKeyed == nil, let el = r.el, el.TagName == n.Tag {
                    self.patchElement(n, el, owner: r.owner)
                }
                next.append(r)
            } else {
                let r = Row(key: k, start: self.doc.CreateTextNode(""), end: self.doc.CreateTextNode(""))
                self.doc.InsertBefore(p, r.start, cursor)
                self.doc.InsertBefore(p, r.end, cursor)
                state.WithOwner(r.owner) {
                    if let mk = n.makeKeyed {
                        if let s = n.sheet { self.note(s) }
                        let built = mk()
                        for c in built.Nodes() { self.build(c, into: p, before: r.end) }
                    } else if !n.Tag.isEmpty {
                        let el = self.doc.CreateElement(n.Tag)
                        r.el = el
                        self.populateElement(n, el, into: p, before: r.end)
                    } else {
                        self.build(n, into: p, before: r.end)
                    }
                }
                next.append(r)
            }
            i += 1
        }
        rows.rows = next
        self.giveSheets()
        self.hosting { runMounted() }
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
    let key: string
    let start: html.Node
    let end: html.Node
    var el: html.Node? = nil
    let owner = state.Owner()

    init(key: string, start: html.Node, end: html.Node) {
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
///
/// focus, where given, is how Focus moves the page's focus
/// (web.Page.Focus); measure, how Bounds finds where an element is
/// (web.Page.BoundsOf).
public func Mount(_ root: () -> Node, into doc: dom.Document, at parent: html.Node, styles: (([string]) -> void)? = nil, focus: ((html.Node?) -> void)? = nil,
                  measure: ((html.Node) -> draw.Rect?)? = nil) -> Mounted {
    let m = Mounted(doc: doc, parent: parent, styles: styles, focus: focus, measure: measure)
    lastMounted = m
    m.hosting {
        state.WithOwner(m.owner) {
            m.Renders += 1
            let nodes = state.Untracked { root().Nodes() }
            for n in nodes { m.build(n, into: parent, before: nil) }
        }
        m.giveSheets()
        runMounted()
    }
    return m
}

// MARK: - Mounting

/// The root whose code is running: being built, or handling an event.
var host: Mounted? = nil
/// The root mounted last, for Focus from code no root is running (a
/// task, a timer).
weak var lastMounted: Mounted? = nil
/// OnMount's work, waiting for the nodes to be in the document.
var toMount: [() -> void] = []

/// Runs f once the nodes the component running now makes are in the
/// document -- to focus a field, measure a box, start a timer. What f
/// makes, and OnCleanup inside it, belong to the component: they end
/// when it is gone.
///
///     @state.State var field: html.Node? = nil
///     OnMount { component.Focus(field) }
///     return <input ref={$field} />
public func OnMount(_ f: () -> void) {
    let owner = state.CurrentOwner()
    let at = frames
    toMount.append({
        let prev = frames
        frames = at
        if let o = owner {
            state.WithOwner(o) { state.Untracked { f() } }
        } else {
            state.Untracked { f() }
        }
        frames = prev
    })
}

/// How deep the build in progress is. OnMount's work waits for the
/// outermost to end: a live region inside an element is built before
/// the element is in the document and its refs are given.
var buildDepth = 0

func runMounted() {
    if buildDepth > 0 { return }
    while !toMount.isEmpty {
        let f = toMount.removeFirst()
        f()
    }
}

/// Moves the page's focus to node -- a field a ref holds -- or, given
/// nil, takes it away. Called from a component's code: OnMount, a
/// handler, an effect; from a task, it is the last mounted root's page.
public func Focus(_ node: html.Node?) {
    if let h = host ?? lastMounted, let f = h.focus { f(node) }
}

/// Where an element a ref holds is in the page's view, as laid out now:
/// to drag it, or to place something beside it. nil when it isn't laid
/// out, or the page can't say.
public func Bounds(of node: html.Node?) -> draw.Rect? {
    guard let n = node, let h = host ?? lastMounted, let f = h.measure else { return nil }
    return f(n)
}
