package webview

import "ui/draw"

/// What a box is laid out against: the width of the containing block,
/// and its height where that is known.
public struct ContainingBlock {
    public var Width: float32
    public var Height: float32?

    public init(width: float32, height: float32?) {
        Width = width
        Height = height
    }
}

/// Lays out a box tree: block flow, lines, flex, positioned boxes.
/// Positions come out relative to each box's parent; the root's are
/// relative to the viewport.
public final class Layout {
    public var ViewportWidth: float32
    public var ViewportHeight: float32

    public init(viewportWidth: float32, viewportHeight: float32) {
        ViewportWidth = viewportWidth
        ViewportHeight = viewportHeight
    }

    /// Lays out the whole tree from the root. The root box fills the
    /// viewport's width; its height is its content's.
    public func Run(_ root: Box) {
        let cb = ContainingBlock(width: ViewportWidth, height: ViewportHeight)
        root.X = 0
        root.Y = 0
        root.Positioned = []
        layoutBlock(root, cb: cb, positionedAncestor: root)
        root.X = root.Margin.Left
        root.Y = root.Margin.Top
        layoutPositioned(root, cb: cb)
    }

    // MARK: - Edges and sizes

    /// Resolves a box's margins, borders and padding against its
    /// containing block's width; auto margins are 0 until the width is
    /// known.
    func resolveEdges(_ box: Box, cbWidth: float32) {
        let s = box.Style
        box.Margin = draw.Edges(s.MarginTop.Or(0, base: cbWidth), s.MarginRight.Or(0, base: cbWidth),
                                s.MarginBottom.Or(0, base: cbWidth), s.MarginLeft.Or(0, base: cbWidth))
        box.Padding = draw.Edges(s.PaddingTop.Or(0, base: cbWidth), s.PaddingRight.Or(0, base: cbWidth),
                                 s.PaddingBottom.Or(0, base: cbWidth), s.PaddingLeft.Or(0, base: cbWidth))
        box.Border = s.BorderWidths
    }

    /// The border-box width a length gives, for box-sizing.
    func borderBoxWidth(_ box: Box, contentWidth: float32) -> float32 {
        return contentWidth + box.Padding.Horizontal + box.Border.Horizontal
    }

    func widthFromStyle(_ box: Box, _ length: Length, cbWidth: float32) -> float32? {
        guard let v = length.Resolve(cbWidth) else { return nil }
        if box.Style.BoxSizing == .borderBox { return v }
        return borderBoxWidth(box, contentWidth: v)
    }

    func heightFromStyle(_ box: Box, _ length: Length, cbHeight: float32?) -> float32? {
        var base: float32 = 0
        if case .percent = length {
            guard let h = cbHeight else { return nil }
            base = h
        }
        guard let v = length.Resolve(base) else { return nil }
        if box.Style.BoxSizing == .borderBox { return v }
        return v + box.Padding.Vertical + box.Border.Vertical
    }

    /// Clamps a border-box width to min-width and max-width.
    func clampWidth(_ box: Box, _ width: float32, cbWidth: float32) -> float32 {
        var w = width
        if let max = widthFromStyle(box, box.Style.MaxWidth, cbWidth: cbWidth), w > max { w = max }
        if let min = widthFromStyle(box, box.Style.MinWidth, cbWidth: cbWidth), w < min { w = min }
        let edges = box.Padding.Horizontal + box.Border.Horizontal
        if w < edges { w = edges }
        return w
    }

    func clampHeight(_ box: Box, _ height: float32, cbHeight: float32?) -> float32 {
        var h = height
        if let max = heightFromStyle(box, box.Style.MaxHeight, cbHeight: cbHeight), h > max { h = max }
        if let min = heightFromStyle(box, box.Style.MinHeight, cbHeight: cbHeight), h < min { h = min }
        let edges = box.Padding.Vertical + box.Border.Vertical
        if h < edges { h = edges }
        return h
    }

    // MARK: - Blocks

    /// Lays out a block-level box in normal flow: its width from the
    /// containing block, its content, then its height. Sets Width,
    /// Height and the edges; the caller places X and Y.
    func layoutBlock(_ box: Box, cb: ContainingBlock, positionedAncestor: Box) {
        resolveEdges(box, cbWidth: cb.Width)
        box.Positioned = []
        let s = box.Style

        if box.Kind == .replaced {
            sizeReplaced(box, cb: cb)
            return
        }

        // Width: given, or the containing block's less the margins.
        let available = cb.Width - box.Margin.Horizontal
        if let w = widthFromStyle(box, s.Width, cbWidth: cb.Width) {
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
            // Auto margins share what is left: centring.
            let free = cb.Width - box.Width
            if s.MarginLeft.IsAuto && s.MarginRight.IsAuto {
                box.Margin.Left = free / 2
                box.Margin.Right = free / 2
            } else if s.MarginLeft.IsAuto {
                box.Margin.Left = free - box.Margin.Right
            } else if s.MarginRight.IsAuto {
                box.Margin.Right = free - box.Margin.Left
            }
        } else if s.Width == .minContent || s.Width == .maxContent || s.Width == .fitContent || box.Style.Float != .none || box.Style.IsOutOfFlow || box.Style.Display == .table || box.Style.Display == .inlineTable {
            let widths = intrinsicWidths(box)
            var w = widths.max
            if s.Width == .minContent { w = widths.min }
            if w > available { w = available > widths.min ? available : widths.min }
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        } else {
            box.Width = clampWidth(box, available > 0 ? available : 0, cbWidth: cb.Width)
        }

        // A height given up front is what the children's percentages
        // measure against.
        let givenHeight = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        box.DefiniteInnerHeight = nil
        if let g = givenHeight {
            box.DefiniteInnerHeight = clampHeight(box, g, cbHeight: cb.Height) - box.Padding.Vertical - box.Border.Vertical
        }
        let contentHeight = layoutContent(box, positionedAncestor: s.IsPositioned ? box : positionedAncestor)

        // Height: given, or the content's.
        var h = contentHeight + box.Padding.Vertical + box.Border.Vertical
        if let given = givenHeight {
            h = given
        }
        box.Height = clampHeight(box, h, cbHeight: cb.Height)
        box.ContentHeight = contentHeight
        applyRelativeOffsets(box, cbWidth: cb.Width, cbHeight: cb.Height)
        if box.Style.IsPositioned {
            layoutPositioned(box, cb: ContainingBlock(width: box.PaddingBoxWidth, height: box.PaddingBoxHeight))
        }
    }

    /// Lays out what a block holds and answers the content height.
    func layoutContent(_ box: Box, positionedAncestor: Box) -> float32 {
        let contentWidth = box.InnerWidth
        var height: float32 = 0
        if box.Style.IsFlexContainer {
            height = layoutFlex(box, contentWidth: contentWidth, positionedAncestor: positionedAncestor)
        } else if box.HasInlineChildren {
            height = layoutInline(box, contentWidth: contentWidth, positionedAncestor: positionedAncestor)
        } else {
            height = layoutBlockChildren(box, contentWidth: contentWidth, positionedAncestor: positionedAncestor)
        }
        return height
    }

    /// Stacks block children top to bottom, collapsing the margins that
    /// meet: adjacent siblings', and a first or last child's with the
    /// parent's where nothing separates them.
    func layoutBlockChildren(_ box: Box, contentWidth: float32, positionedAncestor: Box) -> float32 {
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))
        var y: float32 = 0
        // The margin waiting to be placed: the largest positive and the
        // most negative seen since the last content.
        var positive: float32 = 0
        var negative: float32 = 0
        var first = true
        let canCollapseTop = box.Border.Top == 0 && box.Padding.Top == 0 && !box.IsFormattingRoot
        var firstCollapsed = false
        var lastChild: Box? = nil
        var contentRight: float32 = 0

        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                // Out of flow: its static position is where it would
                // have been.
                child.X = box.ContentX
                child.Y = box.ContentY + y + positive + negative
                positionedAncestor.Positioned.append(child)
                child.Parent = box
                continue
            }
            if child.Style.Float != .none {
                // Floats are laid out in flow for now: as blocks that
                // take their own width, side by side when they fit.
                layoutBlock(child, cb: cb, positionedAncestor: positionedAncestor)
                child.X = box.ContentX + child.Margin.Left
                if child.Style.Float == .right {
                    child.X = box.ContentX + contentWidth - child.Width - child.Margin.Right
                }
                child.Y = box.ContentY + y + positive + negative + child.Margin.Top
                y = child.Y - box.ContentY + child.Height + child.Margin.Bottom
                positive = 0
                negative = 0
                first = false
                lastChild = child
                if child.X + child.Width > contentRight { contentRight = child.X + child.Width }
                continue
            }
            if child.Style.Clear != .none && !first {
                // Nothing to clear past yet: floats live in the flow.
            }
            layoutBlock(child, cb: cb, positionedAncestor: positionedAncestor)

            // The child's top margin joins the pending one.
            let top = child.Margin.Top
            if top >= 0 { if top > positive { positive = top } } else { if top < negative { negative = top } }

            if first && canCollapseTop && collapsesThrough(child, top: true) {
                // The first child's margin escapes to the parent: the
                // parent's top margin becomes the collapsed pair.
                let joined = positive + negative
                box.Margin.Top = collapse(box.Margin.Top, joined)
                positive = 0
                negative = 0
                firstCollapsed = true
            }
            let margin = positive + negative
            child.X = box.ContentX + child.Margin.Left
            child.Y = box.ContentY + y + margin
            y += margin + child.Height
            positive = 0
            negative = 0
            let bottom = child.Margin.Bottom
            if bottom >= 0 { positive = bottom } else { negative = bottom }
            first = false
            lastChild = child
            if child.X + child.Width > contentRight { contentRight = child.X + child.Width }
        }
        _ = firstCollapsed
        // The last child's bottom margin: kept inside the box when the
        // box has a bottom edge or a set height, and otherwise passed to
        // the parent.
        let canCollapseBottom = box.Border.Bottom == 0 && box.Padding.Bottom == 0 && !box.IsFormattingRoot && box.Style.Height.IsAuto
        if lastChild != nil && canCollapseBottom {
            box.Margin.Bottom = collapse(box.Margin.Bottom, positive + negative)
        } else {
            y += positive + negative
        }
        box.ContentWidth = contentRight - box.ContentX
        return y > 0 ? y : 0
    }

    /// Two collapsing margins: the larger of positives, the more negative
    /// of negatives, or their sum when mixed.
    func collapse(_ a: float32, _ b: float32) -> float32 {
        if a >= 0 && b >= 0 { return a > b ? a : b }
        if a < 0 && b < 0 { return a < b ? a : b }
        return a + b
    }

    /// Whether a box's own top (or bottom) margin can collapse with its
    /// parent's: nothing of the box lies between them.
    func collapsesThrough(_ box: Box, top: Bool) -> bool {
        if box.IsFormattingRoot || box.Kind != .block { return false }
        if top { return box.Border.Top == 0 && box.Padding.Top == 0 }
        return box.Border.Bottom == 0 && box.Padding.Bottom == 0
    }

    /// The content height a box's children can take percentages of, if
    /// the box's height is known before its content is.
    func definiteInnerHeight(_ box: Box) -> float32? {
        if let h = box.DefiniteInnerHeight { return h }
        if let h = box.Style.Height.Pixels {
            if box.Style.BoxSizing == .borderBox { return h - box.Padding.Vertical - box.Border.Vertical }
            return h
        }
        return nil
    }

    // MARK: - Replaced and atomic boxes

    /// Sizes an image or control from its style, or its own size.
    func sizeReplaced(_ box: Box, cb: ContainingBlock) {
        let s = box.Style
        var w: float32? = widthFromStyle(box, s.Width, cbWidth: cb.Width)
        var h: float32? = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        let iw = box.IntrinsicWidth
        let ih = box.IntrinsicHeight
        let edgesW = box.Padding.Horizontal + box.Border.Horizontal
        let edgesH = box.Padding.Vertical + box.Border.Vertical
        if w == nil && h == nil {
            w = iw + edgesW
            h = ih + edgesH
        } else if w == nil {
            // Keep the image's proportions.
            let inner = h! - edgesH
            w = (ih > 0 ? inner * iw / ih : iw) + edgesW
        } else if h == nil {
            let inner = w! - edgesW
            h = (iw > 0 ? inner * ih / iw : ih) + edgesH
        }
        box.Width = clampWidth(box, w!, cbWidth: cb.Width)
        if box.Replaced == .image && iw > 0 && ih > 0 && box.Width != w! && s.Height.IsAuto {
            h = (box.Width - edgesW) * ih / iw + edgesH
        }
        box.Height = clampHeight(box, h!, cbHeight: cb.Height)
        box.Baseline = box.Height
        if box.Replaced == .textInput || box.Replaced == .button || box.Replaced == .select {
            let face = s.Face
            let lh = face.LineHeight
            box.Baseline = box.Border.Top + box.Padding.Top + (box.InnerHeight - lh) / 2 + face.Ascent
        }
    }

    /// Lays out an atomic inline box -- inline-block, inline-flex or a
    /// control -- for a line: it takes its own width, up to what the
    /// line offers.
    func layoutAtomic(_ box: Box, cb: ContainingBlock, positionedAncestor: Box) {
        if box.Kind == .replaced {
            resolveEdges(box, cbWidth: cb.Width)
            sizeReplaced(box, cb: cb)
            return
        }
        resolveEdges(box, cbWidth: cb.Width)
        box.Positioned = []
        let s = box.Style
        if let w = widthFromStyle(box, s.Width, cbWidth: cb.Width) {
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        } else {
            let widths = intrinsicWidths(box)
            let available = cb.Width - box.Margin.Horizontal
            var w = widths.max
            if w > available { w = available > widths.min ? available : widths.min }
            box.Width = clampWidth(box, w, cbWidth: cb.Width)
        }
        let givenHeight = heightFromStyle(box, s.Height, cbHeight: cb.Height)
        box.DefiniteInnerHeight = nil
        if let g = givenHeight { box.DefiniteInnerHeight = g - box.Padding.Vertical - box.Border.Vertical }
        let contentHeight = layoutContent(box, positionedAncestor: s.IsPositioned ? box : positionedAncestor)
        var h = contentHeight + box.Padding.Vertical + box.Border.Vertical
        if let given = givenHeight { h = given }
        box.Height = clampHeight(box, h, cbHeight: cb.Height)
        box.ContentHeight = contentHeight
        // The baseline is the last line's, unless overflow hides it.
        box.Baseline = nil
        if !s.ClipsOverflow {
            box.Baseline = lastBaseline(box)
        }
        if box.Style.IsPositioned {
            layoutPositioned(box, cb: ContainingBlock(width: box.PaddingBoxWidth, height: box.PaddingBoxHeight))
        }
    }

    /// The baseline of the last line in a box, from the box's top.
    func lastBaseline(_ box: Box) -> float32? {
        if !box.Lines.isEmpty {
            let line = box.Lines[box.Lines.count - 1]
            return line.Y + line.Baseline
        }
        var i = box.Children.count - 1
        while i >= 0 {
            let c = box.Children[i]
            if c.Kind == .block && !c.Style.IsOutOfFlow {
                if let b = lastBaseline(c) { return c.Y + b }
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Intrinsic widths

    /// The narrowest and widest a box would be if its width were its
    /// content's: the longest word, and the whole content on one line.
    /// Border-box widths.
    func intrinsicWidths(_ box: Box) -> (min: float32, max: float32) {
        return intrinsicWidths(box, ignoringWidth: false)
    }

    func intrinsicWidths(_ box: Box, ignoringWidth: Bool) -> (min: float32, max: float32) {
        let s = box.Style
        let edges = box.Padding.Horizontal + box.Border.Horizontal
        if box.Kind == .replaced {
            if let w = s.Width.Pixels, !ignoringWidth {
                let bw = s.BoxSizing == .borderBox ? w : w + edges
                return (min: bw, max: bw)
            }
            return (min: box.IntrinsicWidth + edges, max: box.IntrinsicWidth + edges)
        }
        if let w = s.Width.Pixels, !ignoringWidth {
            let bw = s.BoxSizing == .borderBox ? w : w + edges
            return (min: bw, max: bw)
        }
        var minW: float32 = 0
        var maxW: float32 = 0
        if s.IsFlexContainer {
            var sumMax: float32 = 0
            var maxMin: float32 = 0
            var sumMin: float32 = 0
            var maxMax: float32 = 0
            var n = 0
            for c in box.Children where !c.Style.IsOutOfFlow {
                resolveEdges(c, cbWidth: 0)
                let w = intrinsicWidths(c)
                sumMax += w.max + c.Margin.Horizontal
                sumMin += w.min + c.Margin.Horizontal
                if w.min + c.Margin.Horizontal > maxMin { maxMin = w.min + c.Margin.Horizontal }
                if w.max + c.Margin.Horizontal > maxMax { maxMax = w.max + c.Margin.Horizontal }
                n += 1
            }
            let gap = s.ColumnGap.Or(0, base: 0) * float32(n > 1 ? n - 1 : 0)
            if s.FlexDirection.IsRow {
                minW = (s.FlexWrap == .nowrap ? sumMin : maxMin) + gap
                maxW = sumMax + gap
            } else {
                minW = maxMin
                maxW = maxMax
            }
        } else if box.HasInlineChildren {
            let w = inlineIntrinsicWidths(box)
            minW = w.min
            maxW = w.max
        } else {
            for c in box.Children where !c.Style.IsOutOfFlow {
                resolveEdges(c, cbWidth: 0)
                let w = intrinsicWidths(c)
                let m = c.Margin.Horizontal
                if w.min + m > minW { minW = w.min + m }
                if w.max + m > maxW { maxW = w.max + m }
            }
        }
        if let max = s.MaxWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? max : max + edges
            if maxW + edges > bw { maxW = bw - edges }
            if minW + edges > bw { minW = bw - edges }
        }
        if let min = s.MinWidth.Pixels {
            let bw = s.BoxSizing == .borderBox ? min : min + edges
            if maxW + edges < bw { maxW = bw - edges }
            if minW + edges < bw { minW = bw - edges }
        }
        return (min: minW + edges, max: maxW + edges)
    }

    // MARK: - Positioned boxes

    /// Lays out the boxes positioned against a box, after its flow: each
    /// against the box's padding box, at its insets, or where it would
    /// have been where it has none.
    func layoutPositioned(_ box: Box, cb: ContainingBlock) {
        if box.Positioned.isEmpty { return }
        let list = box.Positioned
        let padX = box.Kind == .block && box.Parent != nil ? box.PaddingBoxX : 0
        let padY = box.Kind == .block && box.Parent != nil ? box.PaddingBoxY : 0
        let cbWidth = cb.Width
        let cbHeight = cb.Height ?? 0
        for child in list {
            let s = child.Style
            // The static position was written into X and Y by the flow
            // layout, relative to the flow parent; move it to be relative
            // to this containing block.
            var staticX = child.X
            var staticY = child.Y
            var p = child.Parent
            while let parent = p, parent.Id != box.Id {
                staticX += parent.X
                staticY += parent.Y
                p = parent.Parent
            }
            staticX -= padX
            staticY -= padY

            resolveEdges(child, cbWidth: cbWidth)
            let left = s.Left.Resolve(cbWidth)
            let right = s.Right.Resolve(cbWidth)
            let top = s.Top.Resolve(cbHeight)
            let bottom = s.Bottom.Resolve(cbHeight)

            if child.Kind == .replaced {
                sizeReplaced(child, cb: ContainingBlock(width: cbWidth, height: cbHeight))
            } else {
                if let w = widthFromStyle(child, s.Width, cbWidth: cbWidth) {
                    child.Width = clampWidth(child, w, cbWidth: cbWidth)
                } else if let l = left, let r = right {
                    child.Width = clampWidth(child, cbWidth - l - r - child.Margin.Horizontal, cbWidth: cbWidth)
                } else {
                    let widths = intrinsicWidths(child)
                    var available = cbWidth - child.Margin.Horizontal
                    if let l = left { available -= l } else if let r = right { available -= r } else { available -= staticX }
                    var w = widths.max
                    if w > available { w = available > widths.min ? available : widths.min }
                    child.Width = clampWidth(child, w, cbWidth: cbWidth)
                }
                child.Positioned = []
                child.DefiniteInnerHeight = nil
                if let given = heightFromStyle(child, s.Height, cbHeight: cbHeight) {
                    child.DefiniteInnerHeight = given - child.Padding.Vertical - child.Border.Vertical
                } else if let t = top, let b = bottom {
                    child.DefiniteInnerHeight = cbHeight - t - b - child.Margin.Vertical - child.Padding.Vertical - child.Border.Vertical
                }
                let contentHeight = layoutContent(child, positionedAncestor: child)
                var h = contentHeight + child.Padding.Vertical + child.Border.Vertical
                if let given = heightFromStyle(child, s.Height, cbHeight: cbHeight) {
                    h = given
                } else if let t = top, let b = bottom {
                    h = cbHeight - t - b - child.Margin.Vertical
                }
                child.Height = clampHeight(child, h, cbHeight: cbHeight)
                child.ContentHeight = contentHeight
            }
            if let l = left {
                child.X = padX + l + child.Margin.Left
            } else if let r = right {
                child.X = padX + cbWidth - r - child.Width - child.Margin.Right
            } else {
                child.X = padX + staticX + child.Margin.Left
            }
            if let t = top {
                child.Y = padY + t + child.Margin.Top
            } else if let b = bottom {
                child.Y = padY + cbHeight - b - child.Height - child.Margin.Bottom
            } else {
                child.Y = padY + staticY + child.Margin.Top
            }
            child.Parent = box
            layoutPositioned(child, cb: ContainingBlock(width: child.PaddingBoxWidth, height: child.PaddingBoxHeight))
        }
    }

    /// Applies relative positioning after layout: the box is drawn
    /// shifted by its insets, its place in the flow kept.
    func applyRelativeOffsets(_ box: Box, cbWidth: float32, cbHeight: float32?) {
        let s = box.Style
        box.OffsetX = 0
        box.OffsetY = 0
        if s.Position == .relative {
            if let l = s.Left.Resolve(cbWidth) { box.OffsetX = l }
            else if let r = s.Right.Resolve(cbWidth) { box.OffsetX = -r }
            if let t = s.Top.Resolve(cbHeight ?? 0) { box.OffsetY = t }
            else if let b = s.Bottom.Resolve(cbHeight ?? 0) { box.OffsetY = -b }
        }
    }
}
