package webview

import "text/html"
import "ui/window"
import "ui/draw"

extension WebView {
    /// Takes a window event. Pointer events inside the view's bounds,
    /// scrolling, and keys while something in the page has focus are
    /// handled; the rest is ignored and left to the host.
    public func Handle(_ event: window.Event) -> EventResult {
        switch event {
        case .pointerMoved(let p):
            return pointerMoved(p.Position)
        case .pointerDown(let p, let button):
            if !isInside(p.Position) { return .ignored }
            if button == .primary { return pointerDown(p.Position, clicks: p.Clicks) }
            return .handled
        case .pointerUp(let p, let button):
            if button == .primary { return pointerUp(p.Position) }
            return .ignored
        case .pointerLeft:
            pointer = window.Point(-1, -1)
            setHovered(nil)
            return .handled
        case .scrolled(let s):
            if !isInside(pointer) && pointer.X >= 0 { return .ignored }
            return scrolled(s)
        case .keyDown(let k):
            return keyDown(k)
        case .text(let t):
            return typed(t)
        default:
            return .ignored
        }
    }

    func isInside(_ p: window.Point) -> bool {
        return p.X >= origin.X && p.Y >= origin.Y && p.X < origin.X + size.Width && p.Y < origin.Y + size.Height
    }

    // MARK: - Pointer

    func pointerMoved(_ p: window.Point) -> EventResult {
        pointer = p
        if selecting {
            // Dragging extends the selection to the text under the pointer.
            update()
            if let hit = hitAt(clampedToView(p)), let tb = hit.TextBox, let node = tb.Node {
                let focus = TextPosition(Node: node, Offset: hit.TextOffset)
                if selectionFocus?.Node.Id != node.Id || selectionFocus?.Offset != hit.TextOffset {
                    selectionFocus = focus
                    needsPaint = true
                }
            }
            return .handled
        }
        if !isInside(p) {
            setHovered(nil)
            cursor = window.Cursor.arrow
            return .ignored
        }
        update()
        let hit = hitAt(p)
        setHovered(hit?.Node)
        cursor = cursorFor(hit)
        return .handled
    }

    func clampedToView(_ p: window.Point) -> window.Point {
        var q = p
        if q.X < origin.X { q.X = origin.X }
        if q.Y < origin.Y { q.Y = origin.Y }
        if q.X >= origin.X + size.Width { q.X = origin.X + size.Width - 1 }
        if q.Y >= origin.Y + size.Height { q.Y = origin.Y + size.Height - 1 }
        return q
    }

    /// The cursor an element asks for, or what its kind implies.
    func cursorFor(_ hit: Hit?) -> window.Cursor {
        guard let h = hit else { return window.Cursor.arrow }
        var cur: Box? = h.Box
        while let b = cur {
            switch b.Style.Cursor {
            case .pointer: return window.Cursor.pointingHand
            case .text: return window.Cursor.iBeam
            case .crosshair: return window.Cursor.crosshair
            case .ewResize: return window.Cursor.resizeLeftRight
            case .nsResize: return window.Cursor.resizeUpDown
            case .default, .none, .move, .notAllowed, .wait, .help, .grab: return window.Cursor.arrow
            case .auto: break
            }
            if b.Style.Cursor != .auto { break }
            cur = b.Parent
        }
        if h.TextBox != nil && linkAncestor(h.Node) == nil { return window.Cursor.iBeam }
        if let b = h.Box.ElementBox, b.Replaced == .textInput || b.Replaced == .textArea { return window.Cursor.iBeam }
        return window.Cursor.arrow
    }

    func setHovered(_ node: html.Node?) {
        if hovered?.Id == node?.Id { return }
        let oldLink = linkAncestor(hovered)
        hovered = node
        let newLink = linkAncestor(node)
        if oldLink?.Id != newLink?.Id, let cb = onHoverLink {
            if let l = newLink, let href = l.GetAttribute("href") {
                cb(Resolve(href))
            } else {
                cb(nil)
            }
        }
        stateChanged()
    }

    func pointerDown(_ p: window.Point, clicks: int32 = 1) -> EventResult {
        update()
        ClearSelection()
        guard let hit = hitAt(p) else {
            Focus(nil)
            return .handled
        }
        let node = hit.Node
        pressed = node
        stateChanged()

        // A press on text starts a selection, unless it is a link or a
        // control; a double click takes the word, a triple the paragraph.
        if let tb = hit.TextBox, let textNode = tb.Node, controlAncestor(node) == nil && linkAncestor(node) == nil {
            if clicks >= 3 {
                selectBlock(of: tb)
                return .handled
            }
            if clicks == 2 {
                let b = [uint8](tb.Text.utf8)
                var start = min(hit.TextOffset, b.count)
                var end = start
                if start < b.count && isSpaceByte(b[start]) {
                    while start > 0 && isSpaceByte(b[start - 1]) { start -= 1 }
                    while end < b.count && isSpaceByte(b[end]) { end += 1 }
                } else {
                    while start > 0 && !isSpaceByte(b[start - 1]) { start -= 1 }
                    while end < b.count && !isSpaceByte(b[end]) { end += 1 }
                }
                selectionAnchor = TextPosition(Node: textNode, Offset: start)
                selectionFocus = TextPosition(Node: textNode, Offset: end)
                needsPaint = true
                return .handled
            }
            selectionAnchor = TextPosition(Node: textNode, Offset: hit.TextOffset)
            selectionFocus = selectionAnchor
            selecting = true
        }

        // A text field: focus it and put the caret where the click was.
        if let control = controlAncestor(node) {
            let tag = control.TagName
            if tag == "input" {
                let type = lower(control.GetAttribute("type") ?? "text")
                if type == "checkbox" {
                    toggleChecked(control)
                    return .handled
                }
                if type == "radio" {
                    check(control)
                    return .handled
                }
                if type == "submit" || type == "button" || type == "reset" || type == "image" {
                    Focus(control)
                    return .handled
                }
                if !control.HasAttribute("disabled") {
                    Focus(control)
                    placeCaret(control, at: p)
                }
                return .handled
            }
            if tag == "textarea" {
                if !control.HasAttribute("disabled") {
                    Focus(control)
                    placeCaret(control, at: p)
                }
                return .handled
            }
            if tag == "button" || tag == "select" {
                Focus(control)
                return .handled
            }
        }
        if let label = ancestor(node, "label") {
            if let target = labelTarget(label) {
                let type = lower(target.GetAttribute("type") ?? "text")
                if type == "checkbox" { toggleChecked(target) }
                else if type == "radio" { check(target) }
                else { Focus(target) }
                return .handled
            }
        }
        if let summary = ancestor(node, "summary"), let details = summary.Parent, details.TagName == "details" {
            if details.HasAttribute("open") {
                removeAttribute(details, "open")
            } else {
                details.SetAttribute("open", "")
            }
            needsStyle = true
            return .handled
        }
        Focus(nil)
        return .handled
    }

    func pointerUp(_ p: window.Point) -> EventResult {
        let was = pressed
        pressed = nil
        if selecting {
            selecting = false
            if !HasSelection { ClearSelection() }
        }
        stateChanged()
        guard let hit = hitAt(p) else { return .ignored }
        // A click is a press and release on the same element.
        if let w = was, let n = hit.Node, sameOrAncestor(w, n) || sameOrAncestor(n, w) {
            return clicked(hit)
        }
        return .handled
    }

    func clicked(_ hit: Hit) -> EventResult {
        let node = hit.Node
        if let control = controlAncestor(node) {
            if control.TagName == "button" || (control.TagName == "input" && isButtonInput(control)) {
                if !control.HasAttribute("disabled") { activateButton(control) }
                return .handled
            }
        }
        if let link = linkAncestor(node), let href = link.GetAttribute("href") {
            navigate(href)
            return .handled
        }
        return .handled
    }

    func navigate(_ href: string) {
        if href.hasPrefix("#") {
            let b = [uint8](href.utf8)
            let id = draw.stringOf(b, 1, b.count)
            if let target = Document?.ElementById(id) {
                ScrollTo(target)
            } else if id.isEmpty || id == "top" {
                SetScrollOffset(window.Point(0, 0))
            }
            return
        }
        if let cb = onNavigate {
            cb(Resolve(href))
        }
    }

    func activateButton(_ button: html.Node) {
        let type = lower(button.GetAttribute("type") ?? (button.TagName == "button" ? "submit" : "button"))
        if type == "reset" {
            if let form = ancestor(button, "form") { resetForm(form) }
            return
        }
        if type == "submit", let form = ancestor(button, "form") {
            submit(form, submitter: button)
            return
        }
        if let cb = onAction {
            let name = button.GetAttribute("name") ?? (button.GetAttribute("id") ?? "button")
            let value = button.GetAttribute("value") ?? trimSpaces(button.InnerText())
            cb(name, value)
        }
    }

    // MARK: - Scrolling

    func scrolled(_ s: window.Scroll) -> EventResult {
        update()
        let step: float32 = s.Precise ? 1 : 40
        let dy = -s.Delta.Y * step
        let dx = -s.Delta.X * step
        // The innermost scroll container under the pointer takes the
        // scroll while it can; then the page.
        if let hit = hitAt(pointer) {
            var cur: Box? = hit.Box
            while let b = cur {
                if b.Style.IsScrollContainer && b.Kind == .block {
                    let maxY = b.ContentHeight - b.InnerHeight
                    if maxY > 0 && ((dy > 0 && b.ScrollY < maxY) || (dy < 0 && b.ScrollY > 0)) {
                        b.ScrollY = clampf(b.ScrollY + dy, 0, maxY)
                        needsPaint = true
                        return .handled
                    }
                }
                cur = b.Parent
            }
        }
        let before = scroll
        scroll.Y += dy
        scroll.X += dx
        clampScroll()
        if scroll.Y != before.Y || scroll.X != before.X {
            needsRepaint = true
            // What is under the pointer changed.
            if pointer.X >= 0 { _ = pointerMoved(pointer) }
        }
        return .handled
    }

    // MARK: - Keys

    func keyDown(_ k: window.KeyEvent) -> EventResult {
        if let f = focused, isTextControl(f) {
            return editKey(f, k)
        }
        if let f = focused, f.TagName == "select" {
            // Up and down move through the options; Home and End go to
            // the ends; a letter jumps to the next option starting with it.
            var options: [html.Node] = []
            collectTags(f, "option", &options)
            if options.isEmpty { return .ignored }
            var current = -1
            var i = 0
            while i < options.count {
                if options[i].HasAttribute("selected") && current < 0 { current = i }
                i += 1
            }
            if current < 0 { current = 0 }
            var next = current
            switch k.Code {
            case .arrowDown, .arrowRight: next = current + 1 < options.count ? current + 1 : current
            case .arrowUp, .arrowLeft: next = current > 0 ? current - 1 : 0
            case .home: next = 0
            case .end: next = options.count - 1
            case .tab:
                moveFocus(backwards: k.Modifiers.Shift)
                return .handled
            case .escape:
                Focus(nil)
                return .handled
            default:
                let key = [uint8](lower(k.Key).utf8)
                if key.count != 1 { return .ignored }
                var j = 1
                while j <= options.count {
                    let idx = (current + j) % options.count
                    let text = [uint8](lower(trimSpaces(options[idx].InnerText())).utf8)
                    if !text.isEmpty && text[0] == key[0] { next = idx; break }
                    j += 1
                }
            }
            if next != current {
                for o in options { removeAttribute(o, "selected") }
                options[next].SetAttribute("selected", "")
                needsStyle = true
            }
            return .handled
        }
        if k.Code == .tab {
            moveFocus(backwards: k.Modifiers.Shift)
            return .handled
        }
        if let f = focused, k.Code == .enter || k.Code == .space {
            if f.TagName == "button" || (f.TagName == "input" && isButtonInput(f)) {
                activateButton(f)
                return .handled
            }
            if f.TagName == "a", let href = f.GetAttribute("href"), k.Code == .enter {
                navigate(href)
                return .handled
            }
        }
        if k.Modifiers.Meta || k.Modifiers.Control {
            if k.Code == .c {
                let text = SelectedText()
                if !text.isEmpty { window.SetClipboardText(text) }
                return .handled
            }
            if k.Code == .a {
                SelectAll()
                return .handled
            }
        }
        let page = size.Height
        switch k.Code {
        case .arrowDown: scrollBy(0, 40)
        case .arrowUp: scrollBy(0, -40)
        case .arrowLeft: scrollBy(-40, 0)
        case .arrowRight: scrollBy(40, 0)
        case .pageDown: scrollBy(0, page * 0.9)
        case .pageUp: scrollBy(0, -page * 0.9)
        case .space: scrollBy(0, k.Modifiers.Shift ? -page * 0.9 : page * 0.9)
        case .home: SetScrollOffset(window.Point(scroll.X, 0))
        case .end: SetScrollOffset(window.Point(scroll.X, contentHeight))
        default: return .ignored
        }
        return .handled
    }

    func scrollBy(_ dx: float32, _ dy: float32) {
        update()
        SetScrollOffset(window.Point(scroll.X + dx, scroll.Y + dy))
    }

    func typed(_ text: string) -> EventResult {
        guard let f = focused, isTextControl(f), !f.HasAttribute("disabled"), !f.HasAttribute("readonly") else { return .ignored }
        if text.isEmpty { return .ignored }
        let bytes = [uint8](text.utf8)
        // Control characters arrive as keys, not text.
        if bytes.count == 1 && bytes[0] < 32 && bytes[0] != 10 { return .ignored }
        var value = valueOf(f)
        if f.TagName == "input", let max = f.GetAttribute("maxlength") {
            let mb = [uint8](max.utf8)
            let n = int(draw.parseNumber(mb, 0, mb.count))
            if n > 0 && value.utf8.count + bytes.count > n { return .handled }
        }
        value = insertBytes(value, at: caret, bytes)
        caret += bytes.count
        setValue(f, value)
        return .handled
    }

    func editKey(_ f: html.Node, _ k: window.KeyEvent) -> EventResult {
        let value = valueOf(f)
        let bytes = [uint8](value.utf8)
        let editable = !f.HasAttribute("disabled") && !f.HasAttribute("readonly")
        switch k.Code {
        case .backspace:
            if !editable { return .handled }
            if caret > 0 {
                let start = k.Modifiers.Alt ? wordStart(bytes, before: caret) : previousChar(bytes, caret)
                setValue(f, draw.stringOf(bytes, 0, start) + draw.stringOf(bytes, caret, bytes.count))
                caret = start
            }
        case .delete:
            if !editable { return .handled }
            if caret < bytes.count {
                let end = nextChar(bytes, caret)
                setValue(f, draw.stringOf(bytes, 0, caret) + draw.stringOf(bytes, end, bytes.count))
            }
        case .arrowLeft:
            caret = k.Modifiers.Alt ? wordStart(bytes, before: caret) : (k.Modifiers.Meta ? 0 : previousChar(bytes, caret))
            showCaret()
            needsPaint = true
        case .arrowRight:
            caret = k.Modifiers.Alt ? wordEnd(bytes, after: caret) : (k.Modifiers.Meta ? bytes.count : nextChar(bytes, caret))
            showCaret()
            needsPaint = true
        case .home:
            caret = 0
            needsPaint = true
        case .end:
            caret = bytes.count
            needsPaint = true
        case .arrowUp, .arrowDown:
            if f.TagName == "textarea" {
                caret = lineMove(bytes, caret, up: k.Code == .arrowUp)
                needsPaint = true
            } else {
                caret = k.Code == .arrowUp ? 0 : bytes.count
                needsPaint = true
            }
        case .enter:
            if f.TagName == "textarea" {
                if editable {
                    setValue(f, insertBytes(value, at: caret, [10]))
                    caret += 1
                }
            } else if let form = ancestor(f, "form") {
                submit(form, submitter: nil)
            } else if let cb = onAction {
                cb(f.GetAttribute("name") ?? (f.GetAttribute("id") ?? "input"), value)
            }
        case .tab:
            moveFocus(backwards: k.Modifiers.Shift)
        case .escape:
            Focus(nil)
        case .a:
            if k.Modifiers.Meta || k.Modifiers.Control {
                caret = bytes.count
                needsPaint = true
            } else {
                return .ignored
            }
        case .c, .x:
            if k.Modifiers.Meta || k.Modifiers.Control {
                window.SetClipboardText(value)
                if k.Code == .x && editable {
                    setValue(f, "")
                    caret = 0
                }
            } else {
                return .ignored
            }
        case .v:
            if (k.Modifiers.Meta || k.Modifiers.Control) && editable {
                let pasted = window.ClipboardText()
                if !pasted.isEmpty {
                    var text = [uint8](pasted.utf8)
                    if f.TagName != "textarea" {
                        // A single-line field takes the first line.
                        var i = 0
                        while i < text.count && text[i] != 10 && text[i] != 13 { i += 1 }
                        while text.count > i { text.removeLast() }
                    }
                    setValue(f, insertBytes(value, at: caret, text))
                    caret += text.count
                }
            } else {
                return .ignored
            }
        default:
            return .ignored
        }
        return .handled
    }

    /// Moves the caret to where a click landed in a text control.
    func placeCaret(_ control: html.Node, at p: window.Point) {
        guard let box = builder.byNode[control.Id] else { return }
        let pos = pagePosition(box)
        let px = p.X - origin.X + scroll.X - (pos.x + box.ContentX + 1)
        let py = p.Y - origin.Y + scroll.Y - (pos.y + box.ContentY)
        let face = box.Style.Face
        let value = valueOf(control)
        let bytes = [uint8](value.utf8)
        var lineStart = 0
        var lineEnd = bytes.count
        if control.TagName == "textarea" {
            var lineIndex = int(py / face.LineHeight)
            if lineIndex < 0 { lineIndex = 0 }
            var i = 0
            var current = 0
            lineStart = 0
            while i < bytes.count && current < lineIndex {
                if bytes[i] == 10 {
                    current += 1
                    lineStart = i + 1
                }
                i += 1
            }
            lineEnd = lineStart
            while lineEnd < bytes.count && bytes[lineEnd] != 10 { lineEnd += 1 }
        }
        var best = lineStart
        var bestDist: float32 = 1e9
        var i = lineStart
        while i <= lineEnd {
            if i == lineEnd || (bytes[i] & 0xC0) != 0x80 {
                let w = face.Measure(draw.stringOf(bytes, lineStart, i))
                let d = w > px ? w - px : px - w
                if d < bestDist {
                    bestDist = d
                    best = i
                }
            }
            i += 1
        }
        caret = best
        showCaret()
        needsPaint = true
    }

    // MARK: - Focus

    func moveFocus(backwards: Bool) {
        guard let doc = Document else { return }
        var order: [html.Node] = []
        collectFocusable(doc.Root, &order)
        if order.isEmpty { return }
        var index = -1
        if let f = focused {
            var i = 0
            while i < order.count {
                if order[i].Id == f.Id { index = i }
                i += 1
            }
        }
        var next = backwards ? index - 1 : index + 1
        if next >= order.count { next = 0 }
        if next < 0 { next = order.count - 1 }
        Focus(order[next])
        if let f = focused {
            caret = valueOf(f).utf8.count
            ScrollIntoViewIfNeeded(f)
        }
    }

    func collectFocusable(_ node: html.Node, _ out: inout [html.Node]) {
        for c in node.Children where c.Kind == html.NodeKind.element {
            if c.HasAttribute("disabled") { continue }
            let tag = c.TagName
            if tag == "input" {
                let type = lower(c.GetAttribute("type") ?? "text")
                if type != "hidden" { out.append(c) }
            } else if tag == "textarea" || tag == "select" || tag == "button" {
                out.append(c)
            } else if tag == "a" && c.HasAttribute("href") {
                out.append(c)
            } else if c.HasAttribute("tabindex") {
                out.append(c)
            }
            collectFocusable(c, &out)
        }
    }

    /// Scrolls just enough to show an element.
    public func ScrollIntoViewIfNeeded(_ node: html.Node) {
        update()
        guard let b = builder.byNode[node.Id] else { return }
        let pos = pagePosition(b)
        if pos.y < scroll.Y {
            scroll.Y = pos.y
        } else if pos.y + b.Height > scroll.Y + size.Height {
            scroll.Y = pos.y + b.Height - size.Height
        }
        clampScroll()
        needsRepaint = true
    }

    // MARK: - Forms

    func toggleChecked(_ input: html.Node) {
        if input.HasAttribute("disabled") { return }
        if input.HasAttribute("checked") {
            removeAttribute(input, "checked")
        } else {
            input.SetAttribute("checked", "")
        }
        Focus(input)
        needsStyle = true
    }

    func check(_ radio: html.Node) {
        if radio.HasAttribute("disabled") { return }
        if let name = radio.GetAttribute("name"), let doc = Document {
            for other in doc.ElementsByTagName("input") {
                if other.Id != radio.Id && other.GetAttribute("name") == name && lower(other.GetAttribute("type") ?? "") == "radio" {
                    removeAttribute(other, "checked")
                }
            }
        }
        radio.SetAttribute("checked", "")
        Focus(radio)
        needsStyle = true
    }

    func removeAttribute(_ node: html.Node, _ name: string) {
        var kept: [html.Attribute] = []
        for a in node.Attributes where a.Name != name {
            kept.append(a)
        }
        node.Attributes = kept
    }

    func resetForm(_ form: html.Node) {
        var controls: [html.Node] = []
        collectControls(form, &controls)
        for c in controls {
            values.removeValue(forKey: c.Id)
        }
        needsStyle = true
    }

    func submit(_ form: html.Node, submitter: html.Node?) {
        var controls: [html.Node] = []
        collectControls(form, &controls)
        var fields: [FormField] = []
        for c in controls {
            guard let name = c.GetAttribute("name"), !name.isEmpty else { continue }
            if c.HasAttribute("disabled") { continue }
            let tag = c.TagName
            if tag == "input" {
                let type = lower(c.GetAttribute("type") ?? "text")
                if type == "checkbox" || type == "radio" {
                    if c.HasAttribute("checked") { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "on")) }
                    continue
                }
                if type == "submit" || type == "button" || type == "reset" || type == "image" {
                    if let s = submitter, s.Id == c.Id { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "")) }
                    continue
                }
                fields.append(FormField(Name: name, Value: valueOf(c)))
            } else if tag == "textarea" {
                fields.append(FormField(Name: name, Value: valueOf(c)))
            } else if tag == "select" {
                fields.append(FormField(Name: name, Value: selectedValue(c)))
            } else if tag == "button" {
                if let s = submitter, s.Id == c.Id { fields.append(FormField(Name: name, Value: c.GetAttribute("value") ?? "")) }
            }
        }
        let action = form.GetAttribute("action") ?? ""
        let method = lower(form.GetAttribute("method") ?? "get")
        if let cb = onSubmit {
            cb(Submission(Action: Resolve(action), Method: method, Fields: fields))
        } else if let cb = onAction {
            cb(form.GetAttribute("name") ?? (form.GetAttribute("id") ?? "form"), action)
        }
    }

    func selectedValue(_ select: html.Node) -> string {
        var options: [html.Node] = []
        collectTags(select, "option", &options)
        var first: html.Node? = nil
        for o in options {
            if first == nil { first = o }
            if o.HasAttribute("selected") { return o.GetAttribute("value") ?? trimSpaces(o.InnerText()) }
        }
        if let f = first { return f.GetAttribute("value") ?? trimSpaces(f.InnerText()) }
        return ""
    }

    func collectControls(_ node: html.Node, _ out: inout [html.Node]) {
        for c in node.Children where c.Kind == html.NodeKind.element {
            let tag = c.TagName
            if tag == "input" || tag == "textarea" || tag == "select" || tag == "button" {
                out.append(c)
            }
            collectControls(c, &out)
        }
    }

    func labelTarget(_ label: html.Node) -> html.Node? {
        if let id = label.GetAttribute("for"), let doc = Document {
            return doc.ElementById(id)
        }
        var controls: [html.Node] = []
        collectControls(label, &controls)
        return controls.first
    }
}

// MARK: - Helpers

func isTextControl(_ node: html.Node) -> bool {
    if node.TagName == "textarea" { return true }
    if node.TagName != "input" { return false }
    let type = lower(node.GetAttribute("type") ?? "text")
    switch type {
    case "text", "password", "search", "email", "url", "tel", "number", "": return true
    default: return false
    }
}

func isButtonInput(_ node: html.Node) -> bool {
    let type = lower(node.GetAttribute("type") ?? "text")
    return type == "submit" || type == "button" || type == "reset" || type == "image"
}

func ancestor(_ node: html.Node?, _ tag: string) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element && n.TagName == tag { return n }
        cur = n.Parent
    }
    return nil
}

func linkAncestor(_ node: html.Node?) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element && (n.TagName == "a" || n.TagName == "area") && n.HasAttribute("href") { return n }
        cur = n.Parent
    }
    return nil
}

func controlAncestor(_ node: html.Node?) -> html.Node? {
    var cur = node
    while let n = cur {
        if n.Kind == html.NodeKind.element {
            let t = n.TagName
            if t == "input" || t == "textarea" || t == "button" || t == "select" { return n }
        }
        cur = n.Parent
    }
    return nil
}

func sameOrAncestor(_ a: html.Node, _ b: html.Node) -> bool {
    var cur: html.Node? = b
    while let n = cur {
        if n.Id == a.Id { return true }
        cur = n.Parent
    }
    return false
}

func insertBytes(_ s: string, at index: int, _ insertion: [uint8]) -> string {
    let b = [uint8](s.utf8)
    let at = index < 0 ? 0 : (index > b.count ? b.count : index)
    var out: [uint8] = []
    var i = 0
    while i < at { out.append(b[i]); i += 1 }
    for x in insertion { out.append(x) }
    while i < b.count { out.append(b[i]); i += 1 }
    return draw.stringOf(out, 0, out.count)
}

func previousChar(_ b: [uint8], _ i: int) -> int {
    var j = i - 1
    while j > 0 && (b[j] & 0xC0) == 0x80 { j -= 1 }
    return j < 0 ? 0 : j
}

func nextChar(_ b: [uint8], _ i: int) -> int {
    var j = i + 1
    while j < b.count && (b[j] & 0xC0) == 0x80 { j += 1 }
    return j > b.count ? b.count : j
}

func wordStart(_ b: [uint8], before i: int) -> int {
    var j = i
    while j > 0 && isSpaceByte(b[j - 1]) { j -= 1 }
    while j > 0 && !isSpaceByte(b[j - 1]) { j -= 1 }
    return j
}

func wordEnd(_ b: [uint8], after i: int) -> int {
    var j = i
    while j < b.count && isSpaceByte(b[j]) { j += 1 }
    while j < b.count && !isSpaceByte(b[j]) { j += 1 }
    return j
}

/// The caret moved a line up or down in multi-line text, keeping its
/// column where the line allows.
func lineMove(_ b: [uint8], _ caret: int, up: Bool) -> int {
    var lineStart = caret
    while lineStart > 0 && b[lineStart - 1] != 10 { lineStart -= 1 }
    let column = caret - lineStart
    if up {
        if lineStart == 0 { return 0 }
        var prevStart = lineStart - 1
        while prevStart > 0 && b[prevStart - 1] != 10 { prevStart -= 1 }
        let prevLen = lineStart - 1 - prevStart
        return prevStart + (column < prevLen ? column : prevLen)
    }
    var lineEnd = caret
    while lineEnd < b.count && b[lineEnd] != 10 { lineEnd += 1 }
    if lineEnd >= b.count { return b.count }
    let nextStart = lineEnd + 1
    var nextEnd = nextStart
    while nextEnd < b.count && b[nextEnd] != 10 { nextEnd += 1 }
    let nextLen = nextEnd - nextStart
    return nextStart + (column < nextLen ? column : nextLen)
}
