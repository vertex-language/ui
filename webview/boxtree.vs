package webview

import "text/html"
import "text/css/selector"
import "ui/draw"

/// What the box tree builder needs from the view: styles, the page's
/// state, and images.
public final class BoxTreeBuilder {
    let resolver: StyleResolver
    let context: selector.MatchContext
    /// Images by URL, for <img> boxes; missing ones are laid out with
    /// their attributes' size, or none.
    public var Images: [string: draw.Image] = [:]
    /// The text a form control holds, by node, where the user has typed
    /// into it; otherwise the DOM's value.
    public var Values: [int64: string] = [:]
    /// Every box made, by node id, for the view to find an element's box.
    public var byNode: [int64: Box] = [:]
    /// Each text node's place in document order, for ordering selections.
    public var textOrder: [int64: int] = [:]
    var textCount = 0

    public init(resolver: StyleResolver, context: selector.MatchContext) {
        self.resolver = resolver
        self.context = context
    }

    /// The box tree of a document: the root element's box, or nil for a
    /// document with no element.
    public func Build(_ doc: html.Document) -> Box? {
        byNode = [:]
        resolver.StateTrace.removeAll(keepingCapacity: true)
        textOrder = [:]
        textCount = 0
        var rootNode: html.Node? = nil
        for c in doc.Root.Children {
            if c.Kind == html.NodeKind.element {
                rootNode = c
                break
            }
        }
        guard let root = rootNode else { return nil }
        let style = resolver.Resolve(root, parent: nil, context: context)
        if style.Display == .none { return nil }
        let box = Box(kind: .block, style: style, node: root)
        byNode[root.Id] = box
        buildChildren(of: root, into: box, parentStyle: style)
        return box
    }

    /// Makes the boxes of a node's children and places them under a
    /// parent box, wrapping inline runs in anonymous blocks where they
    /// sit beside blocks.
    func buildChildren(of node: html.Node, into parent: Box, parentStyle: ComputedStyle) {
        var made: [Box] = []
        appendChildBoxes(of: node, parentStyle: parentStyle, into: &made)
        place(made, into: parent)
    }

    /// Whether children become flex items: blocks, each of its own.
    func place(_ made: [Box], into parent: Box) {
        if made.isEmpty { return }
        if isTableInternal(parent.Style.Display) {
            // Rows and groups hold cells and rows; loose text is dropped
            // and a loose inline is wrapped as a cell would be.
            var run: [Box] = []
            for b in made {
                if b.Kind == .text && isBlank(b.Text) { continue }
                if b.Kind == .block {
                    flushInline(&run, into: parent)
                    parent.AppendChild(b)
                } else {
                    run.append(b)
                }
            }
            flushInline(&run, into: parent)
            return
        }
        let flex = parent.Style.IsFlexContainer || parent.Style.IsGridContainer
        if flex {
            // Every child element is a flex item, blockified; a run of
            // text between them becomes an anonymous block item, and
            // whitespace-only text nothing.
            var run: [Box] = []
            for b in made {
                if b.Kind == .text {
                    if !isBlank(b.Text) { run.append(b) }
                    continue
                }
                flushInline(&run, into: parent)
                if b.Kind == .inline || b.Kind == .inlineBlock {
                    b.Kind = .block
                    b.Style.Display = b.Style.Display.Blockified
                } else if b.Kind == .lineBreak {
                    continue
                }
                parent.AppendChild(b)
            }
            flushInline(&run, into: parent)
            return
        }
        // Floats and positioned boxes go with the inline content around
        // them; only in-flow blocks split it.
        var hasBlock = false
        var hasInline = false
        for b in made {
            if b.Kind == .block && !b.Style.IsOutOfFlow { hasBlock = true } else if !(b.Kind == .text && isBlank(b.Text)) { hasInline = true }
        }
        if hasBlock && hasInline {
            var run: [Box] = []
            for b in made {
                if b.Kind == .block && !b.Style.IsOutOfFlow {
                    flushInline(&run, into: parent)
                    parent.AppendChild(b)
                } else {
                    run.append(b)
                }
            }
            flushInline(&run, into: parent)
        } else if hasBlock {
            for b in made where b.Kind == .block {
                parent.AppendChild(b)
            }
        } else {
            for b in made {
                parent.AppendChild(b)
            }
        }
    }

    /// Wraps a run of inline-level boxes in an anonymous block.
    func flushInline(_ run: inout [Box], into parent: Box) {
        if run.isEmpty { return }
        var allBlank = true
        for b in run {
            if !(b.Kind == .text && isBlank(b.Text)) { allBlank = false }
        }
        if allBlank {
            run = []
            return
        }
        // A run that is only floats and positioned boxes, with blank
        // text: they go straight into the parent.
        var onlyOutOfFlow = true
        for b in run {
            if !(b.Style.IsOutOfFlow || (b.Kind == .text && isBlank(b.Text))) { onlyOutOfFlow = false }
        }
        if onlyOutOfFlow {
            for b in run where b.Style.IsOutOfFlow { parent.AppendChild(b) }
            run = []
            return
        }
        let style = ComputedStyle(inheriting: parent.Style)
        style.Display = .block
        let anon = Box(kind: .block, style: style, node: nil)
        anon.IsAnonymous = true
        for b in run {
            anon.AppendChild(b)
        }
        parent.AppendChild(anon)
        run = []
    }

    func appendChildBoxes(of node: html.Node, parentStyle: ComputedStyle, into out: inout [Box]) {
        var listIndex = 0
        for child in node.Children {
            switch child.Kind {
            case .text:
                if child.Text.isEmpty { continue }
                let t = Box(kind: .text, style: parentStyle, node: child)
                t.Text = child.Text
                textCount += 1
                textOrder[child.Id] = textCount
                out.append(t)
            case .element:
                let style = resolver.Resolve(child, parent: parentStyle, context: context)
                if style.Display == .none { continue }
                if style.Display == .contents {
                    appendChildBoxes(of: child, parentStyle: style, into: &out)
                    continue
                }
                if let box = makeBox(child, style: style, parentStyle: parentStyle, listIndex: &listIndex) {
                    out.append(box)
                }
            default:
                continue
            }
        }
    }

    /// The box for an element, with its children's boxes under it.
    func makeBox(_ node: html.Node, style: ComputedStyle, parentStyle: ComputedStyle, listIndex: inout int) -> Box? {
        let tag = node.TagName
        var box: Box
        switch tag {
        case "img":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .image
            if let src = node.GetAttribute("src"), let img = Images[src] {
                box.Image = img
                box.IntrinsicWidth = float32(img.Width)
                box.IntrinsicHeight = float32(img.Height)
            } else {
                box.IntrinsicWidth = 0
                box.IntrinsicHeight = 0
            }
        case "input":
            let type = lower(node.GetAttribute("type") ?? "text")
            box = Box(kind: .replaced, style: style, node: node)
            switch type {
            case "checkbox":
                box.Replaced = .checkbox
                box.IntrinsicWidth = 13
                box.IntrinsicHeight = 13
            case "radio":
                box.Replaced = .radio
                box.IntrinsicWidth = 13
                box.IntrinsicHeight = 13
            case "submit", "button", "reset", "image":
                box.Replaced = .button
                box.Text = node.GetAttribute("value") ?? (type == "submit" ? "Submit" : (type == "reset" ? "Reset" : ""))
                let face = style.Face
                box.IntrinsicWidth = face.Measure(box.Text) + 20
                box.IntrinsicHeight = face.LineHeight + 6
            case "range", "color", "file", "date", "time", "month", "week", "datetime-local":
                box.Replaced = .placeholder
                box.IntrinsicWidth = 150
                box.IntrinsicHeight = 24
            default:
                box.Replaced = .textInput
                box.Text = Values[node.Id] ?? (node.GetAttribute("value") ?? "")
                box.IntrinsicWidth = 150
                box.IntrinsicHeight = 24
            }
        case "textarea":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .textArea
            box.Text = Values[node.Id] ?? node.InnerText()
            box.IntrinsicWidth = 200
            box.IntrinsicHeight = 60
        case "select":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .select
            box.Text = selectedOptionText(node)
            box.IntrinsicWidth = style.Face.Measure(box.Text) + 34
            box.IntrinsicHeight = 24
        case "progress", "meter":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .progress
            box.IntrinsicWidth = 160
            box.IntrinsicHeight = 16
        case "video", "iframe", "canvas", "embed", "object", "svg":
            box = Box(kind: .replaced, style: style, node: node)
            box.Replaced = .placeholder
            box.IntrinsicWidth = 300
            box.IntrinsicHeight = 150
        case "br":
            box = Box(kind: .lineBreak, style: style, node: node)
        default:
            let kind = kindFor(style.Display)
            box = Box(kind: kind, style: style, node: node)
            if style.Display == .listItem {
                listIndex += 1
                if let start = node.Parent?.GetAttribute("start") {
                    let b = [uint8](start.utf8)
                    let n = int(draw.parseNumber(b, 0, b.count))
                    if listIndex == 1 && n > 0 { listIndex = n }
                }
                if let value = node.GetAttribute("value") {
                    let b = [uint8](value.utf8)
                    let n = int(draw.parseNumber(b, 0, b.count))
                    if n > 0 { listIndex = n }
                }
                box.Marker = markerText(style.ListStyleType, listIndex, node: node)
            }
            byNode[node.Id] = box
            buildChildren(of: node, into: box, parentStyle: style)
            addPseudoElements(node, box, style)
            return box
        }
        byNode[node.Id] = box
        return box
    }

    /// Adds the boxes of ::before and ::after where rules give them
    /// content: first and last among the element's children.
    func addPseudoElements(_ node: html.Node, _ box: Box, _ style: ComputedStyle) {
        if !resolver.HasPseudoElements { return }
        if let before = resolver.ResolvePseudo(node, "before", parent: style, context: context) {
            if let made = pseudoBox(node, before) {
                made.Parent = box
                box.Children.insert(made, at: 0)
                if box.Children.count > 1 { regroup(box) }
            }
        }
        if let after = resolver.ResolvePseudo(node, "after", parent: style, context: context) {
            if let made = pseudoBox(node, after) {
                box.AppendChild(made)
                if box.Children.count > 1 { regroup(box) }
            }
        }
    }

    /// The box of a pseudo-element: its display, holding its content
    /// as text. attr() reads the element's attribute.
    func pseudoBox(_ node: html.Node, _ style: ComputedStyle) -> Box? {
        guard let parts = style.Content else { return nil }
        var text = ""
        for part in parts {
            let b = [uint8](part.utf8)
            if !b.isEmpty && b[0] == 1 {
                text += node.GetAttribute(draw.stringOf(b, 1, b.count)) ?? ""
            } else {
                text += part
            }
        }
        if style.Display == .none { return nil }
        let kind = kindFor(style.Display)
        let box = Box(kind: kind, style: style, node: nil)
        box.IsAnonymous = true
        if !text.isEmpty {
            let t = Box(kind: .text, style: style, node: nil)
            t.Text = text
            box.AppendChild(t)
        }
        return box
    }

    /// Wraps inline runs again after a pseudo-element joined the
    /// children, so blocks and inlines stay apart.
    func regroup(_ box: Box) {
        var made: [Box] = []
        for c in box.Children {
            if c.IsAnonymous && c.Kind == .block && c.Node == nil && c.Style.Content == nil {
                // An anonymous wrapper from before: unwrap it.
                for inner in c.Children { made.append(inner) }
            } else {
                made.append(c)
            }
        }
        box.Children = []
        place(made, into: box)
    }

    func kindFor(_ display: Display) -> BoxKind {
        switch display {
        case .inline: return .inline
        case .inlineBlock, .inlineFlex, .inlineGrid, .inlineTable: return .inlineBlock
        default: return .block
        }
    }

    /// Whether a box is a part of a table other than a cell: a row, a
    /// row group, a column. Text in one is not content.
    func isTableInternal(_ display: Display) -> bool {
        switch display {
        case .table, .inlineTable, .tableRow, .tableRowGroup, .tableHeaderGroup, .tableFooterGroup, .tableColumn, .tableColumnGroup:
            return true
        default:
            return false
        }
    }

    func selectedOptionText(_ select: html.Node) -> string {
        var first = ""
        var found = ""
        walkOptions(select, &first, &found)
        return found.isEmpty ? first : found
    }

    func walkOptions(_ n: html.Node, _ first: inout string, _ found: inout string) {
        for c in n.Children {
            if c.Kind == html.NodeKind.element {
                if c.TagName == "option" {
                    let text = trimSpaces(c.InnerText())
                    if first.isEmpty { first = text }
                    if c.HasAttribute("selected") && found.isEmpty { found = text }
                } else {
                    walkOptions(c, &first, &found)
                }
            }
        }
    }
}

func isBlank(_ s: string) -> bool {
    for b in s.utf8 {
        if !isSpaceByte(b) { return false }
    }
    return true
}

/// The marker a list item shows for its list-style-type and index.
func markerText(_ type: ListStyleType, _ index: int, node: html.Node) -> string {
    switch type {
    case .none: return ""
    case .disc: return "•"
    case .circle: return "◦"
    case .square: return "▪"
    case .decimal: return "\(index)."
    case .decimalLeadingZero: return index < 10 ? "0\(index)." : "\(index)."
    case .lowerAlpha: return alpha(index, upper: false) + "."
    case .upperAlpha: return alpha(index, upper: true) + "."
    case .lowerRoman: return roman(index, upper: false) + "."
    case .upperRoman: return roman(index, upper: true) + "."
    }
}
