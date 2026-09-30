package component

import (
    "reactive"
    "web/dom"
    "web/html"
)

/// A root put into a document: its nodes are the children of the element
/// it was mounted at, kept up to date until it is unmounted.
public final class Mounted {
    let doc: dom.Document
    let parent: html.Node
    let root: () -> Node
    let styles: (([string]) -> void)?
    var sheets: [string] = []
    var effect: reactive.Effect? = nil
    /// Where the root's states are kept between renders.
    let slots = reactive.Slots()
    /// The listeners each element was given, by the element's node id,
    /// for the next patch to take away.
    var listeners: [int64: [dom.ListenerID]] = [:]
    /// How many times the root has been rendered.
    public internal(set) var Renders = 0

    init(doc: dom.Document, parent: html.Node, root: () -> Node, styles: (([string]) -> void)?) {
        self.doc = doc
        self.parent = parent
        self.root = root
        self.styles = styles
    }

    /// Stops following the root, and takes its nodes out of the document.
    public func Unmount() {
        effect?.Dispose()
        effect = nil
        for c in parent.Children { remove(c) }
    }

    func render() {
        Renders += 1
        var nodes: [Node] = []
        reactive.WithSlots(slots) { nodes = self.root().Nodes() }
        // The stylesheets the tree's packages carry, handed on when they
        // change: a package's appear with its first element.
        if let give = styles {
            let css = SheetsOf(nodes).map { $0.CSS }
            if css != sheets {
                sheets = css
                give(css)
            }
        }
        patchChildren(parent, nodes)
    }

    // MARK: - Patching

    /// Makes parent's children what nodes describe, reusing each child
    /// that is already the same kind of node in the same place.
    func patchChildren(_ parent: html.Node, _ nodes: [Node]) {
        let have = parent.Children
        var i = 0
        while i < nodes.count {
            let want = nodes[i]
            if i < have.count && same(have[i], want) {
                patch(have[i], want)
            } else if i < have.count {
                let fresh = create(want)
                doc.InsertBefore(parent, fresh, have[i])
                remove(have[i])
            } else {
                doc.AppendChild(parent, create(want))
            }
            i += 1
        }
        while i < have.count {
            remove(have[i])
            i += 1
        }
    }

    /// Whether a document node can be patched into what a node describes.
    func same(_ n: html.Node, _ want: Node) -> bool {
        if want.isText { return n.Kind == html.NodeKind.text }
        return n.Kind == html.NodeKind.element && n.TagName == want.Tag
    }

    func patch(_ n: html.Node, _ want: Node) {
        if want.isText {
            if n.Text != want.Text { doc.SetText(n, want.Text) }
            return
        }
        let attrs = want.attributes()
        // Attributes no longer given go; the rest are set, which records
        // nothing where the value is unchanged.
        var stale: [string] = []
        for a in n.Attributes {
            var kept = false
            for (name, _) in attrs where name == a.Name { kept = true }
            if !kept { stale.append(a.Name) }
        }
        for name in stale { doc.RemoveAttribute(n, name) }
        for (name, value) in attrs { doc.SetAttribute(n, name, value) }
        listen(n, want)
        patchChildren(n, want.Children)
    }

    func create(_ want: Node) -> html.Node {
        if want.isText { return doc.CreateTextNode(want.Text) }
        let n = doc.CreateElement(want.Tag)
        for (name, value) in want.attributes() { doc.SetAttribute(n, name, value) }
        listen(n, want)
        for c in want.Children { doc.AppendChild(n, create(c)) }
        return n
    }

    /// Gives an element the node's handlers, in place of the ones the
    /// last render gave it.
    func listen(_ n: html.Node, _ want: Node) {
        if let old = listeners[n.Id] {
            for id in old { doc.RemoveEventListener(n, id) }
            listeners[n.Id] = nil
        }
        if want.handlers.isEmpty { return }
        var ids: [dom.ListenerID] = []
        for (event, h) in want.handlers {
            ids.append(doc.AddEventListener(n, event, h))
        }
        listeners[n.Id] = ids
    }

    func remove(_ n: html.Node) {
        forget(n)
        doc.RemoveEventListeners(within: n)
        if let p = n.Parent { doc.RemoveChild(p, n) }
    }

    func forget(_ n: html.Node) {
        listeners[n.Id] = nil
        for c in n.Children { forget(c) }
    }
}

/// Puts what root makes into a document, as the children of parent, and
/// keeps it there: when a signal root read changes, root runs again and
/// the document is patched to match. styles is given the stylesheets the
/// tree's packages carry, in cascade order, whenever they change: a page
/// sets them (web.Page.SetStyleSheets).
public func Mount(_ root: () -> Node, into doc: dom.Document, at parent: html.Node, styles: (([string]) -> void)? = nil) -> Mounted {
    let m = Mounted(doc: doc, parent: parent, root: root, styles: styles)
    m.effect = reactive.Effect { m.render() }
    return m
}
