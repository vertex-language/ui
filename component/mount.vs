package component

import (
    "image/draw"
    "ui/state"
    "web/dom"
    "web/html"
)

// The reconciler. What a Node became in a document is an Inst, kept so the
// next description of the same place is applied to it rather than made
// again: an element keeps its element and has its attributes, handlers and
// children patched; a component keeps its fiber (its hooks) and renders
// again; a live region runs its new expression. Siblings are matched by
// key where they have one, by place among the unkeyed where they don't,
// and an Inst is reused only for a Node of its kind (and an element only
// for its tag): anything else is made anew, and what it replaces ends.

enum InstKind {
    case text
    case element
    case fragment
    case fiber
    case region
}

func kindOf(n: Node) -> InstKind {
    if n.isText { return .text }
    if n.fiber != nil { return .fiber }
    if n.live != nil { return .region }
    if !n.Tag.isEmpty { return .element }
    return .fragment
}

/// One made node: a text, an element, or a range (a fragment, a
/// component, a live region) between two empty texts.
final class Inst {
    let kind: InstKind
    let key: string
    /// A text's or an element's node.
    var dom: html.Node? = nil
    /// Around a range's nodes.
    var start: html.Node? = nil
    var end: html.Node? = nil
    var children: [Inst] = []
    // An element's tag, the attributes the reconciler set, its handlers
    // (one listener per event, calling the handlers now), its refs, and
    // its live attributes' bindings.
    var tag = ""
    var setAttrs: [string] = []
    var handlers: [(string, (dom.Event) -> void)] = []
    var listening: [string] = []
    var captureHandlers: [(string, (dom.Event) -> void)] = []
    var capturing: [string] = []
    var refs: [(html.Node?) -> void] = []
    let attrBindings = state.Owner()
    /// A component's fiber.
    var fiber: ComponentFiber? = nil
    /// A live region's expression, and the binding that runs it.
    var live: (() -> [Node])? = nil
    let binding = state.Owner()

    init(kind: InstKind, key: string) {
        self.kind = kind
        self.key = key
    }

    var first: html.Node? { return dom ?? start }
    var last: html.Node? { return dom ?? end }
}

/// A root put into a document: its nodes are made as the children of the
/// element it was mounted at, and kept up to date -- a component when its
/// state is set, a live part when what it read changes -- until the root
/// is unmounted.
public final class Mounted {
    let doc: dom.Document
    let parent: html.Node
    let styles: (([string]) -> void)?
    let focus: ((html.Node?) -> void)?
    let measure: ((html.Node) -> draw.Rect?)?
    var roots: [Inst] = []
    var used: [Sheet] = []
    var given: [string] = []
    /// How many times the root has run: once.
    public internal(set) var Renders = 0
    /// How many times a live part or a component has run, the first time
    /// included.
    public internal(set) var Updates = 0

    init(doc: dom.Document, parent: html.Node, styles: (([string]) -> void)?, focus: ((html.Node?) -> void)?, measure: ((html.Node) -> draw.Rect?)?) {
        self.doc = doc
        self.parent = parent
        self.styles = styles
        self.focus = focus
        self.measure = measure
    }

    /// Ends every component and binding, and takes the root's nodes out of
    /// the document.
    public func Unmount() {
        for r in roots { unmount(r, detach: true) }
        roots = []
    }

    // MARK: - Reconciling

    /// What next becomes among old, in parent before end (nil: at its
    /// end): old reused where it matches, made where nothing does, the rest
    /// ended; then put in next's order.
    func reconcile(old: [Inst], next: [Node], in parent: html.Node, end: html.Node?) -> [Inst] {
        buildDepth += 1
        var taken = [bool](repeating: false, count: old.count)
        var match: [int] = []
        var unkeyed: [int] = []
        var i = 0
        while i < old.count {
            if old[i].key.isEmpty { unkeyed.append(i) }
            i += 1
        }
        var u = 0
        for n in next {
            var found = -1
            if !n.key.isEmpty {
                var j = 0
                while j < old.count {
                    if !taken[j] && old[j].key == n.key && compatible(old[j], n) {
                        found = j
                        break
                    }
                    j += 1
                }
            } else if u < unkeyed.count {
                let j = unkeyed[u]
                u += 1
                if !taken[j] && compatible(old[j], n) { found = j }
            }
            if found >= 0 { taken[found] = true }
            match.append(found)
        }
        i = 0
        while i < old.count {
            if !taken[i] { unmount(old[i], detach: true) }
            i += 1
        }
        var out: [Inst] = []
        i = 0
        while i < next.count {
            if match[i] >= 0 {
                let inst = old[match[i]]
                patch(inst, next[i])
                out.append(inst)
            } else {
                out.append(make(next[i], into: parent, before: end))
            }
            i += 1
        }
        // From the last, each just before what follows it: what is in its
        // place already is not moved.
        var ref = end
        var k = out.count - 1
        while k >= 0 {
            let inst = out[k]
            if let l = inst.last, !sameNode(l.NextSibling(), ref) { move(inst, in: parent, before: ref) }
            ref = inst.first
            k -= 1
        }
        buildDepth -= 1
        return out
    }

    func compatible(inst: Inst, n: Node) -> bool {
        if inst.kind != kindOf(n) { return false }
        if inst.kind == .element { return inst.tag == n.Tag }
        if inst.kind == .fiber, let a = inst.fiber, let b = n.fiber { return a.type == b.type }
        return true
    }

    func move(inst: Inst, in parent: html.Node, before: html.Node?) {
        if let d = inst.dom {
            doc.InsertBefore(parent, d, before)
            return
        }
        guard let s = inst.start, let e = inst.end else { return }
        for c in [s] + between(s, e) + [e] { doc.InsertBefore(parent, c, before) }
    }

    // MARK: - Making

    func make(n: Node, into parent: html.Node, before: html.Node?) -> Inst {
        if let s = n.sheet { note(s) }
        let inst = Inst(kind: kindOf(n), key: n.key)
        switch inst.kind {
        case .text:
            let t = doc.CreateTextNode(n.Text)
            inst.dom = t
            doc.InsertBefore(parent, t, before)
        case .element:
            let el = doc.CreateElement(n.Tag)
            inst.dom = el
            inst.tag = n.Tag
            applyAttributes(inst, n, el)
            listen(inst, n, el)
            inst.children = reconcile([], n.Children, in: el, end: nil)
            doc.InsertBefore(parent, el, before)
            inst.refs = n.refs
            for give in n.refs {
                let g = give
                toMount.append({ g(el) })
            }
            for (name, _) in n.attrs where name == "autofocus" {
                let me = self
                toMount.append({ me.focus?(el) })
                break
            }
        case .fragment:
            markers(inst, parent, before)
            inst.children = reconcile([], n.Children, in: parent, end: inst.end)
        case .fiber:
            markers(inst, parent, before)
            let fiber = n.fiber!
            inst.fiber = fiber
            state.WithOwner(fiber.owner) {
                _ = state.Effect {
                    _ = fiber.trigger.Value
                    state.Untracked { self.renderFiber(inst) }
                }
            }
            // A ref on a component: its first element.
            inst.refs = n.refs
            for give in n.refs {
                let g = give
                toMount.append({ g(firstElement(inst)) })
            }
        case .region:
            markers(inst, parent, before)
            inst.live = n.live
            bindRegion(inst)
        }
        return inst
    }

    func markers(inst: Inst, parent: html.Node, before: html.Node?) {
        let s = doc.CreateTextNode("")
        let e = doc.CreateTextNode("")
        doc.InsertBefore(parent, s, before)
        doc.InsertBefore(parent, e, before)
        inst.start = s
        inst.end = e
    }

    // MARK: - Patching

    /// Applies n to inst, which it is compatible with.
    func patch(inst: Inst, n: Node) {
        if let s = n.sheet { note(s) }
        switch inst.kind {
        case .text:
            if let t = inst.dom, t.Text != n.Text { doc.SetText(t, n.Text) }
        case .element:
            let el = inst.dom!
            applyAttributes(inst, n, el)
            listen(inst, n, el)
            inst.refs = n.refs
            inst.children = reconcile(inst.children, n.Children, in: el, end: nil)
        case .fragment:
            if let e = inst.end, let p = e.Parent {
                inst.children = reconcile(inst.children, n.Children, in: p, end: e)
            }
        case .fiber:
            // The fiber stays, with its hooks; it renders the new props.
            if let f = inst.fiber, let nf = n.fiber { f.renderFn = nf.renderFn }
            inst.refs = n.refs
            renderFiber(inst)
        case .region:
            inst.live = n.live
            bindRegion(inst)
        }
    }

    /// An element's attributes as n gives them: the static ones set, the
    /// ones the last description set and this one does not removed, and
    /// the live ones bound again.
    func applyAttributes(inst: Inst, n: Node, el: html.Node) {
        var hasLiveClass = false
        var hasLiveStyle = false
        var names: [string] = []
        for (name, _) in n.liveAttrs {
            if name == "class" { hasLiveClass = true }
            if name == "style" { hasLiveStyle = true }
            names.append(name)
        }
        var fixed = n.attrs
        if !hasLiveClass, let c = n.classNow() { fixed.append(("class", c)) }
        if !hasLiveStyle, let st = n.styleNow() { fixed.append(("style", st)) }
        for (name, _) in fixed { names.append(name) }
        for old in inst.setAttrs where !names.contains(old) { doc.RemoveAttribute(el, old) }
        inst.setAttrs = names
        for (name, value) in fixed { doc.SetAttribute(el, name, value) }
        inst.attrBindings.Dispose()
        state.WithOwner(inst.attrBindings) {
            for (name, f) in n.liveAttrs {
                let nm = name
                let g = f
                self.bind { self.set(el, nm, g()) }
            }
        }
    }

    /// The element's handlers as n gives them: one listener per event,
    /// added once, calling whichever handlers the last description gave.
    func listen(inst: Inst, n: Node, el: html.Node) {
        inst.handlers = n.handlers
        inst.captureHandlers = n.captureHandlers
        for (event, _) in n.handlers where !inst.listening.contains(event) {
            inst.listening.append(event)
            let ev = event
            _ = doc.AddEventListener(el, ev, { e in
                self.hosting {
                    for (name, h) in inst.handlers where name == ev { h(e) }
                }
            })
        }
        for (event, _) in n.captureHandlers where !inst.capturing.contains(event) {
            inst.capturing.append(event)
            let ev = event
            _ = doc.AddEventListener(el, ev, capture: true, { e in
                self.hosting {
                    for (name, h) in inst.captureHandlers where name == ev { h(e) }
                }
            })
        }
    }

    /// Renders a component and applies what it gives to its range; its
    /// effects wait for the nodes to be in the document.
    func renderFiber(inst: Inst) {
        guard let fiber = inst.fiber, !fiber.unmounted, let e = inst.end, let p = e.Parent else { return }
        Updates += 1
        let nodes = fiber.render().Nodes()
        inst.children = reconcile(inst.children, nodes, in: p, end: e)
        queueEffects(fiber)
        giveSheets()
        hosting { runMounted() }
    }

    /// A live region's binding, made again for its expression: it runs it,
    /// and again when a signal it read changes, and applies the nodes it
    /// gives to its range.
    func bindRegion(inst: Inst) {
        inst.binding.Dispose()
        guard let f = inst.live else { return }
        state.WithOwner(inst.binding) {
            _ = state.Effect {
                self.Updates += 1
                let nodes = f()
                state.Untracked {
                    guard let e = inst.end, let p = e.Parent else { return }
                    inst.children = self.reconcile(inst.children, nodes, in: p, end: e)
                    self.giveSheets()
                    self.hosting { runMounted() }
                }
            }
        }
    }

    /// A fiber's effects from the render just made, run once its nodes
    /// are in the document and its refs are given: after the outermost
    /// build ends, a child's before its parent's.
    func queueEffects(fiber: ComponentFiber) {
        let effs = fiber.effects
        fiber.effects = []
        if effs.isEmpty { return }
        let me = self
        toEffect.append({
            if fiber.unmounted { return }
            me.hosting {
                for eff in effs { eff() }
            }
        })
    }

    // MARK: - Ending

    /// Ends what inst made: its bindings, its component, its refs; and,
    /// where detach, takes its nodes out (an element's children go with
    /// it).
    func unmount(inst: Inst, detach: bool) {
        let ranged = inst.dom == nil
        for c in inst.children { unmount(c, detach: ranged && detach) }
        inst.children = []
        inst.attrBindings.Dispose()
        inst.binding.Dispose()
        if let f = inst.fiber { f.dispose() }
        for g in inst.refs { g(nil) }
        inst.refs = []
        if let d = inst.dom {
            doc.RemoveEventListeners(within: d)
            if detach, let p = d.Parent { doc.RemoveChild(p, d) }
        }
        if detach {
            if let s = inst.start, let p = s.Parent { doc.RemoveChild(p, s) }
            if let e = inst.end, let p = e.Parent { doc.RemoveChild(p, e) }
        }
    }

    // MARK: - Helpers

    /// Runs body as this root's code: what it calls Focus on is focused
    /// in this root's page.
    func hosting(body: () -> void) {
        let prev = host
        host = self
        body()
        host = prev
    }

    /// A binding: an effect owned by what is being made, counted.
    func bind(f: () -> void) {
        _ = state.Effect {
            self.Updates += 1
            f()
        }
    }

    func set(el: html.Node, name: string, value: string?) {
        if let v = value {
            doc.SetAttribute(el, name, v)
        } else {
            doc.RemoveAttribute(el, name)
        }
    }

    /// The nodes strictly between two markers.
    func between(start: html.Node, end: html.Node) -> [html.Node] {
        var out: [html.Node] = []
        var c = start.NextSibling()
        while let n = c, n !== end {
            out.append(n)
            c = n.NextSibling()
        }
        return out
    }

    // MARK: - Styles

    func note(s: Sheet) {
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

/// The first element an Inst made: itself, or the first inside its range.
func firstElement(inst: Inst) -> html.Node? {
    if let d = inst.dom { return d.Kind == html.NodeKind.element ? d : nil }
    for c in inst.children {
        if let e = firstElement(c) { return e }
    }
    return nil
}

func sameNode(a: html.Node?, b: html.Node?) -> bool {
    if let x = a, let y = b { return x === y }
    return a == nil && b == nil
}

/// Puts what root makes into a document, as the children of parent. The
/// root runs once; its components and live parts keep themselves up to
/// date. styles is given the stylesheets the nodes' packages carry, in
/// cascade order, whenever they change: a page sets them
/// (web.Page.SetStyleSheets).
///
/// focus, where given, is how Focus moves the page's focus
/// (web.Page.Focus); measure, how Bounds finds where an element is
/// (web.Page.BoundsOf).
public func Mount(root: () -> Node, into doc: dom.Document, at parent: html.Node, styles: (([string]) -> void)? = nil, focus: ((html.Node?) -> void)? = nil,
                  measure: ((html.Node) -> draw.Rect?)? = nil) -> Mounted {
    let m = Mounted(doc: doc, parent: parent, styles: styles, focus: focus, measure: measure)
    lastMounted = m
    m.hosting {
        m.Renders += 1
        let nodes = state.Untracked { root().Nodes() }
        m.roots = m.reconcile([], nodes, in: parent, end: nil)
        m.giveSheets()
        runMounted()
    }
    return m
}

// MARK: - Committing

/// The root whose code is running: being built, or handling an event.
var host: Mounted? = nil
/// The root mounted last, for Focus from code no root is running (a
/// task, a timer).
weak var lastMounted: Mounted? = nil
/// What waits for the nodes to be in the document: refs, autofocus.
var toMount: [() -> void] = []
/// Components' effects, waiting for toMount: an effect sees its refs.
var toEffect: [() -> void] = []

/// How deep the build in progress is. What waits for the nodes to be in
/// the document waits for the outermost to end: a live region inside an
/// element is built before the element is in the document.
var buildDepth = 0

func runMounted() {
    if buildDepth > 0 { return }
    while !toMount.isEmpty || !toEffect.isEmpty {
        if !toMount.isEmpty {
            let f = toMount.removeFirst()
            f()
        } else {
            let f = toEffect.removeFirst()
            f()
        }
    }
}

/// Moves the page's focus to node -- a field a ref holds -- or, given
/// nil, takes it away. Called from a component's code: an effect, a
/// handler; from a task, it is the last mounted root's page.
public func Focus(node: html.Node?) {
    if let h = host ?? lastMounted, let f = h.focus { f(node) }
}

public func Focus<T>(ref: Ref<T>) {
    if let n = ref.current as? html.Node { Focus(n) }
}

/// Where an element a ref holds is in the page's view, as laid out now:
/// to drag it, or to place something beside it. nil when it isn't laid
/// out, or the page can't say.
public func Bounds(of node: html.Node?) -> draw.Rect? {
    guard let n = node, let h = host ?? lastMounted, let f = h.measure else { return nil }
    return f(n)
}

public func Bounds<T>(of ref: Ref<T>) -> draw.Rect? {
    if let n = ref.current as? html.Node { return Bounds(of: n) }
    return nil
}
