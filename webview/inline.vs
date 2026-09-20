package webview

import "ui/draw"
import "ui/font"

enum ItemKind: Equatable {
    case word
    case space
    case open
    case close
    case atomic
    case lineBreak
    case newline
    case float
}

/// One thing inline layout places: a word, a space, the start or end of
/// an inline element, an atomic box, or a break.
struct Item {
    var kind: ItemKind
    var box: Box
    var owner: Box
    var text: string
    var run: font.Run
    var width: float32
    var offset: int
    var length: int
    var breakable: bool
    var decoration: TextDecoration
    var decorationColor: draw.Color

    init(kind: ItemKind, box: Box, owner: Box) {
        self.kind = kind
        self.box = box
        self.owner = owner
        text = ""
        run = font.Run()
        width = 0
        offset = 0
        length = 0
        breakable = true
        decoration = TextDecoration()
        decorationColor = draw.Color.black
    }
}

/// An inline element open while a line is being built: where on the
/// line it began, and whether it began on this line.
struct OpenSpan {
    var box: Box
    var startX: float32
    var isFirst: bool
}

extension Layout {
    /// Lays out a block container's inline content as lines and answers
    /// the content height.
    func layoutInline(_ box: Box, contentWidth: float32, flow: Flow) -> float32 {
        box.Lines = []
        var items: [Item] = []
        var pendingSpace = false
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))
        let rootX = flow.x + box.ContentX
        let rootY = flow.y + box.ContentY
        collectItems(box, owner: box, cb: cb, flow: flow,
                     decoration: box.Style.TextDecoration, decorationColor: box.Style.TextDecorationColor ?? box.Style.Color,
                     into: &items, pendingSpace: &pendingSpace)
        // A collapsing space at the very end never shows.
        while let last = items.last, last.kind == .space, last.owner.Style.WhiteSpace.Collapses {
            items.removeLast()
        }
        if items.isEmpty && box.Marker.isEmpty {
            return 0
        }

        let indent = box.Style.TextIndent.Or(0, base: contentWidth)
        var y: float32 = 0
        var lineItems: [Item] = []
        var lineWidth: float32 = 0
        var open: [OpenSpan] = []
        var lineHasContent = false
        var firstLine = true
        var contentRight: float32 = 0
        // A line may break before a word only where a space came before
        // it: not between a word and the punctuation stuck to it.
        var breakOpportunity = true
        // Floats met in the text go to the side at the next line's top.
        var pendingFloats: [Box] = []
        let strutHeight = box.Style.LineHeightPx
        let floats = flow.floats

        // Where the current line starts and how wide it is, between the
        // floats that reach it.
        func band() -> (start: float32, width: float32) {
            let b = floats.intrusions(y: rootY + y, height: strutHeight, left: rootX, right: rootX + contentWidth)
            return (start: b.left - rootX, width: b.right - b.left)
        }

        func available() -> float32 {
            return band().width - (firstLine ? indent : 0)
        }

        func narrowed() -> bool {
            return band().width < contentWidth - 0.01
        }

        func placePendingFloats() {
            for f in pendingFloats {
                let placed = floats.place(f, left: f.Style.Float == .left, y: rootY + y,
                                          containerLeft: rootX, containerRight: rootX + contentWidth)
                f.X = placed.x - rootX + box.ContentX + f.Margin.Left
                f.Y = placed.y - rootY + box.ContentY + f.Margin.Top
            }
            pendingFloats = []
        }

        func finishLine(forced: Bool) {
            // Trailing spaces hang off the line: they take no room.
            while let last = lineItems.last, last.kind == .space, last.owner.Style.WhiteSpace.Collapses {
                lineItems.removeLast()
            }
            if !lineHasContent && !forced && !firstLine {
                lineItems = []
                lineWidth = 0
                placePendingFloats()
                return
            }
            let b = band()
            let line = buildLine(box, items: lineItems, y: y, startX: b.start, contentWidth: b.width,
                                 indent: firstLine ? indent : 0, open: &open, isFirst: firstLine)
            box.Lines.append(line)
            y += line.Height
            for f in line.Fragments {
                if f.X + f.Width > contentRight { contentRight = f.X + f.Width }
            }
            lineItems = []
            lineWidth = 0
            lineHasContent = false
            firstLine = false
            placePendingFloats()
        }

        placePendingFloats()
        for item in items {
            switch item.kind {
            case .float:
                // Beside the line's content when it fits there, else at
                // the top of the next line.
                if lineHasContent && lineWidth + item.box.OuterWidth > available() + 0.01 {
                    pendingFloats.append(item.box)
                } else {
                    let placed = floats.place(item.box, left: item.box.Style.Float == .left, y: rootY + y,
                                              containerLeft: rootX, containerRight: rootX + contentWidth)
                    item.box.X = placed.x - rootX + box.ContentX + item.box.Margin.Left
                    item.box.Y = placed.y - rootY + box.ContentY + item.box.Margin.Top
                }
            case .space:
                breakOpportunity = true
                // Spaces that collapse never start a line; preserved
                // ones do.
                if !lineHasContent && item.owner.Style.WhiteSpace.Collapses { continue }
                lineItems.append(item)
                lineWidth += item.width
                if !item.owner.Style.WhiteSpace.Collapses { lineHasContent = true }
            case .word, .atomic:
                let canBreak = breakOpportunity || item.kind == .atomic
                breakOpportunity = item.kind == .atomic
                // An empty line squeezed by floats that cannot hold the
                // word moves down to where the floats end.
                var guardRounds = 0
                while !lineHasContent && item.width > available() + 0.01 && narrowed() && guardRounds < 64 {
                    guardRounds += 1
                    guard let next = floats.nextBand(after: rootY + y) else { break }
                    y = next - rootY
                }
                if lineHasContent && item.breakable && canBreak && lineWidth + item.width > available() + 0.01 {
                    // Break before the item, at the last space. The
                    // starts of inline elements just before it belong
                    // with it on the new line.
                    var carried: [Item] = []
                    while let last = lineItems.last, last.kind == .open {
                        carried.insert(last, at: 0)
                        lineWidth -= last.width
                        lineItems.removeLast()
                        if let idx = lastIndex(open, of: last.box) { open.remove(at: idx) }
                    }
                    finishLine(forced: false)
                    for c in carried {
                        lineItems.append(c)
                        lineWidth += c.width
                    }
                }
                lineItems.append(item)
                lineWidth += item.width
                lineHasContent = true
            case .open, .close:
                lineItems.append(item)
                lineWidth += item.width
            case .lineBreak, .newline:
                lineItems.append(item)
                finishLine(forced: true)
                breakOpportunity = true
            }
        }
        if lineHasContent || box.Lines.isEmpty {
            finishLine(forced: true)
        }
        box.ContentWidth = contentRight - box.ContentX
        return y
    }

    /// Gathers the items of a box's inline content, in order.
    func collectItems(_ box: Box, owner: Box, cb: ContainingBlock, flow: Flow,
                      decoration: TextDecoration, decorationColor: draw.Color,
                      into items: inout [Item], pendingSpace: inout Bool) {
        let positionedAncestor = flow.positioned
        for child in box.Children {
            if child.Style.Float != .none && child.Kind != .text {
                // A float in the text, whatever kind of box: laid out
                // now, placed when the line it is in is known.
                layoutBlock(child, cb: cb, flow: flow.root(child))
                items.append(Item(kind: .float, box: child, owner: owner))
                pendingSpace = false
                continue
            }
            switch child.Kind {
            case .text:
                textItems(child, owner: owner, decoration: decoration, decorationColor: decorationColor,
                          into: &items, pendingSpace: &pendingSpace)
            case .inline:
                if child.Style.Position == .absolute || child.Style.Position == .fixed {
                    child.X = 0
                    child.Y = 0
                    positionedAncestor.Positioned.append(child)
                    continue
                }
                resolveEdges(child, cbWidth: cb.Width)
                var openItem = Item(kind: .open, box: child, owner: child)
                openItem.width = child.Margin.Left + child.Border.Left + child.Padding.Left
                items.append(openItem)
                let deco = decoration.Union(child.Style.TextDecoration)
                let decoColor = child.Style.TextDecoration.IsNone ? decorationColor : (child.Style.TextDecorationColor ?? child.Style.Color)
                collectItems(child, owner: child, cb: cb, flow: flow,
                             decoration: deco, decorationColor: decoColor, into: &items, pendingSpace: &pendingSpace)
                var closeItem = Item(kind: .close, box: child, owner: child)
                closeItem.width = child.Margin.Right + child.Border.Right + child.Padding.Right
                items.append(closeItem)
            case .inlineBlock, .replaced:
                if child.Style.Position == .absolute || child.Style.Position == .fixed {
                    child.X = 0
                    child.Y = 0
                    positionedAncestor.Positioned.append(child)
                    continue
                }
                layoutAtomic(child, cb: cb, flow: flow)
                var item = Item(kind: .atomic, box: child, owner: owner)
                item.width = child.OuterWidth
                item.breakable = owner.Style.WhiteSpace.Wraps
                items.append(item)
                pendingSpace = false
            case .lineBreak:
                items.append(Item(kind: .lineBreak, box: child, owner: owner))
                pendingSpace = false
            case .block:
                if child.Style.Float != .none {
                    // A float in the text: laid out now, placed when the
                    // line it is in is known.
                    layoutBlock(child, cb: cb, flow: flow.root(child))
                    items.append(Item(kind: .float, box: child, owner: owner))
                    continue
                }
                // Anonymous wrapping keeps blocks out of inline content;
                // one that got here is laid out as its own line.
                layoutBlock(child, cb: cb, flow: flow)
                var item = Item(kind: .atomic, box: child, owner: owner)
                item.width = child.OuterWidth
                items.append(item)
            }
        }
    }

    /// Splits a text box into words and spaces as its white-space says.
    func textItems(_ box: Box, owner: Box, decoration: TextDecoration, decorationColor: draw.Color,
                   into items: inout [Item], pendingSpace: inout Bool) {
        let style = owner.Style
        let face = style.Face
        var bytes = [uint8](box.Text.utf8)
        switch style.TextTransform {
        case .uppercase: bytes = upperBytes(bytes)
        case .lowercase: bytes = lowerBytes(bytes)
        case .capitalize: bytes = capitalizeBytes(bytes)
        case .none: break
        }
        let ws = style.WhiteSpace
        let collapses = ws.Collapses
        let keepsNewlines = ws.KeepsNewlines
        let wraps = ws.Wraps
        let spaceWidth = face.SpaceWidth + style.WordSpacing + style.LetterSpacing
        var i = 0
        let n = bytes.count
        while i < n {
            let b = bytes[i]
            if b == 10 && keepsNewlines {
                var item = Item(kind: .newline, box: box, owner: owner)
                item.offset = i
                item.length = 1
                items.append(item)
                pendingSpace = false
                i += 1
                continue
            }
            if isSpaceByte(b) {
                if collapses {
                    // One space for the run, and none after another.
                    var j = i
                    while j < n && isSpaceByte(bytes[j]) && !(bytes[j] == 10 && keepsNewlines) { j += 1 }
                    if !pendingSpace {
                        var item = Item(kind: .space, box: box, owner: owner)
                        item.width = spaceWidth
                        item.offset = i
                        item.length = j - i
                        item.text = " "
                        item.breakable = wraps
                        items.append(item)
                        pendingSpace = true
                    }
                    i = j
                } else {
                    // pre and pre-wrap: every space shows.
                    var j = i
                    var count = 0
                    while j < n && isSpaceByte(bytes[j]) && bytes[j] != 10 {
                        if bytes[j] == 9 {
                            count += int(style.TabSize)
                        } else {
                            count += 1
                        }
                        j += 1
                    }
                    var item = Item(kind: .space, box: box, owner: owner)
                    item.width = spaceWidth * float32(count)
                    item.offset = i
                    item.length = j - i
                    item.text = spaces(count)
                    item.breakable = wraps
                    items.append(item)
                    i = j
                }
                continue
            }
            var j = i
            while j < n && !isSpaceByte(bytes[j]) { j += 1 }
            let word = draw.stringOf(bytes, i, j)
            var item = Item(kind: .word, box: box, owner: owner)
            item.text = word
            item.run = face.Shape(word)
            item.width = item.run.Width + style.LetterSpacing * float32(item.run.Count)
            item.offset = i
            item.length = j - i
            item.breakable = wraps
            item.decoration = decoration
            item.decorationColor = decorationColor
            items.append(item)
            pendingSpace = false
            i = j
        }
    }

    /// Makes a line from its items: places them left to right, merges
    /// neighbouring text of one box into fragments, aligns everything
    /// vertically, and applies text-align.
    func buildLine(_ box: Box, items: [Item], y: float32, startX: float32, contentWidth: float32, indent: float32,
                   open: inout [OpenSpan], isFirst: Bool) -> Line {
        let strutStyle = box.Style
        let strutFace = strutStyle.Face
        var line = Line(x: box.ContentX + startX, y: box.ContentY + y, width: contentWidth)

        var fragments: [Fragment] = []
        var x: float32 = indent
        // Spans open from earlier lines continue at the line's start.
        var i = 0
        while i < open.count {
            open[i].startX = x
            open[i].isFirst = false
            i += 1
        }
        var spans: [Span] = []

        func emitSpan(_ o: OpenSpan, endX: float32, isLast: Bool) {
            let b = o.box
            let face = b.Style.Face
            var sp = Span(Box: b, X: o.startX, Y: 0, Width: endX - o.startX, Height: face.Ascent + face.Descent,
                          IsFirst: o.isFirst, IsLast: isLast)
            if o.isFirst { sp.X += b.Margin.Left; sp.Width -= b.Margin.Left }
            if isLast { sp.Width -= b.Margin.Right }
            spans.append(sp)
        }

        for item in items {
            switch item.kind {
            case .word, .space:
                // Join with the previous fragment when it is the same text
                // in the same style.
                if let last = fragments.last, last.Kind == .text, last.Box.Id == item.box.Id, last.Owner.Id == item.owner.Id {
                    var f = fragments[fragments.count - 1]
                    f.Text += item.text
                    f.Run.Glyphs.append(contentsOf: item.run.Glyphs)
                    f.Run.Faces.append(contentsOf: item.run.Faces)
                    f.Run.Advances.append(contentsOf: item.run.Advances)
                    if item.kind == .space {
                        // A space has no glyphs of its own: advance the pen by one.
                        f.Run.Glyphs.append(0)
                        f.Run.Faces.append(0)
                        f.Run.Advances.append(item.width)
                    }
                    f.Run.Width += item.width
                    f.Width += item.width
                    fragments[fragments.count - 1] = f
                } else {
                    var f = Fragment(kind: .text, box: item.box, owner: item.owner)
                    f.X = x
                    f.Width = item.width
                    f.Text = item.text
                    f.Run = item.run
                    if item.kind == .space {
                        f.Run.Glyphs.append(0)
                        f.Run.Faces.append(0)
                        f.Run.Advances.append(item.width)
                        f.Run.Width = item.width
                    }
                    f.Offset = item.offset
                    f.Decoration = item.decoration
                    f.DecorationColor = item.decorationColor
                    fragments.append(f)
                }
                x += item.width
            case .atomic:
                var f = Fragment(kind: .atomic, box: item.box, owner: item.owner)
                f.X = x
                f.Width = item.width
                fragments.append(f)
                x += item.width
            case .open:
                open.append(OpenSpan(box: item.box, startX: x, isFirst: true))
                x += item.width
            case .close:
                x += item.width
                if let idx = lastIndex(open, of: item.box) {
                    emitSpan(open[idx], endX: x, isLast: true)
                    open.remove(at: idx)
                }
            case .lineBreak, .newline, .float:
                break
            }
        }
        // Spans still open run to the line's end.
        for o in open {
            emitSpan(o, endX: x, isLast: false)
        }
        let used = x

        // Vertical metrics: each fragment's box around the baseline.
        let strutAscent = strutFace.Ascent
        let strutDescent = strutFace.Descent
        let strutLH = strutStyle.LineHeightPx
        let strutHalf = (strutLH - (strutAscent + strutDescent)) / 2
        var top: float32 = -(strutAscent + strutHalf)
        var bottom: float32 = strutDescent + strutHalf
        var shifts: [float32] = []
        var aligned: [VerticalAlign] = []
        i = 0
        while i < fragments.count {
            var f = fragments[i]
            let ownerStyle = f.Owner.Style
            var shift: float32 = 0
            var va = ownerStyle.VerticalAlign
            if f.Kind == .atomic {
                let b = f.Box
                va = b.Style.VerticalAlign
                f.Height = b.OuterHeight
                let baseline = b.Baseline ?? (b.Height + b.Margin.Bottom)
                f.Ascent = baseline + b.Margin.Top
                if b.Baseline == nil { f.Ascent = f.Height }
            } else {
                let face = ownerStyle.Face
                let lh = ownerStyle.LineHeightPx
                let half = (lh - (face.Ascent + face.Descent)) / 2
                f.Ascent = face.Ascent + half
                f.Height = lh
            }
            switch va {
            case .baseline: shift = 0
            case .sub: shift = ownerStyle.FontSize * 0.2
            case .super: shift = -ownerStyle.FontSize * 0.35
            case .middle:
                let parentFace = strutFace
                let mid = f.Ascent - f.Height / 2
                shift = mid - parentFace.XHeight / 2
            case .textTop:
                shift = f.Ascent - strutAscent
            case .textBottom:
                shift = strutDescent - (f.Height - f.Ascent)
            case .length(let l):
                shift = -(l.Or(0, base: ownerStyle.LineHeightPx))
            case .top, .bottom:
                shift = 0
            }
            shifts.append(shift)
            aligned.append(va)
            if va != .top && va != .bottom {
                let t = -f.Ascent + shift
                let b = (f.Height - f.Ascent) + shift
                if t < top { top = t }
                if b > bottom { bottom = b }
            }
            fragments[i] = f
            i += 1
        }
        var lineHeight = bottom - top
        // Boxes aligned to the line's top or bottom may make it taller.
        i = 0
        while i < fragments.count {
            if aligned[i] == .top || aligned[i] == .bottom {
                if fragments[i].Height > lineHeight { lineHeight = fragments[i].Height }
            }
            i += 1
        }
        if aligned.count > 0 {
            // Room added above extends the line downward from the top.
            let extra = lineHeight - (bottom - top)
            if extra > 0 { bottom += extra }
        }
        let baseline = -top
        line.Height = bottom - top
        line.Baseline = baseline

        // Horizontal alignment.
        var dx: float32 = 0
        let free = contentWidth - used
        if free > 0 {
            switch strutStyle.TextAlign {
            case .center: dx = free / 2
            case .right, .end: dx = free
            default: dx = 0
            }
        }

        i = 0
        while i < fragments.count {
            var f = fragments[i]
            f.X += line.X + dx
            switch aligned[i] {
            case .top:
                f.Y = line.Y
            case .bottom:
                f.Y = line.Y + line.Height - f.Height
            default:
                f.Y = line.Y + baseline - f.Ascent + shifts[i]
            }
            if f.Kind == .atomic {
                let b = f.Box
                b.X = f.X + b.Margin.Left
                b.Y = f.Y + b.Margin.Top
            }
            fragments[i] = f
            i += 1
        }
        i = 0
        while i < spans.count {
            var sp = spans[i]
            let b = sp.Box
            let face = b.Style.Face
            sp.X += line.X + dx
            sp.Y = line.Y + baseline - face.Ascent - b.Padding.Top - b.Border.Top
            sp.Height = face.Ascent + face.Descent + b.Padding.Vertical + b.Border.Vertical
            spans[i] = sp
            i += 1
        }
        line.Fragments = fragments
        line.Spans = spans

        // A list marker sits outside the first line, or starts it.
        if isFirst && !box.Marker.isEmpty {
            var m = Fragment(kind: .marker, box: box, owner: box)
            m.Text = box.Marker
            m.Run = strutFace.Shape(box.Marker)
            m.Width = m.Run.Width
            m.Ascent = strutAscent + strutHalf
            m.Height = strutLH
            m.Y = line.Y + baseline - m.Ascent
            if box.Style.ListStylePosition == .inside {
                m.X = line.X + dx
                var k = 0
                while k < line.Fragments.count {
                    line.Fragments[k].X += m.Width + strutFace.SpaceWidth
                    k += 1
                }
                k = 0
                while k < line.Spans.count {
                    line.Spans[k].X += m.Width + strutFace.SpaceWidth
                    k += 1
                }
            } else {
                m.X = line.X - m.Width - strutFace.SpaceWidth * 1.5
            }
            line.Fragments.insert(m, at: 0)
        }
        return line
    }

    /// The widest and narrowest the inline content of a box can be.
    func inlineIntrinsicWidths(_ box: Box) -> (min: float32, max: float32) {
        var items: [Item] = []
        var pendingSpace = false
        let cb = ContainingBlock(width: 0, height: nil)
        collectItems(box, owner: box, cb: cb, flow: Flow(positioned: box, floats: FloatContext(), x: 0, y: 0),
                     decoration: TextDecoration(), decorationColor: box.Style.Color,
                     into: &items, pendingSpace: &pendingSpace)
        var lineMax: float32 = 0
        var maxW: float32 = 0
        var minW: float32 = 0
        var current: float32 = 0
        for item in items {
            switch item.kind {
            case .lineBreak, .newline:
                if lineMax > maxW { maxW = lineMax }
                lineMax = 0
                if current > minW { minW = current }
                current = 0
            case .space:
                lineMax += item.width
                if item.breakable {
                    if current > minW { minW = current }
                    current = 0
                } else {
                    current += item.width
                }
            case .atomic, .float:
                lineMax += item.width
                if current > minW { minW = current }
                current = item.width
                if current > minW { minW = current }
                current = 0
            default:
                lineMax += item.width
                current += item.width
            }
        }
        if lineMax > maxW { maxW = lineMax }
        if current > minW { minW = current }
        return (min: minW, max: maxW)
    }
}

func lastIndex(_ list: [OpenSpan], of box: Box) -> int? {
    var i = list.count - 1
    while i >= 0 {
        if list[i].box.Id == box.Id { return i }
        i -= 1
    }
    return nil
}

func spaces(_ n: int) -> string {
    var out = ""
    var i = 0
    while i < n {
        out += " "
        i += 1
    }
    return out
}
