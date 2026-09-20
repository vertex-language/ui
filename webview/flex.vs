package webview

/// A flex item while its line is being sized.
struct FlexItem {
    var box: Box
    var basis: float32
    var main: float32
    var cross: float32
    var minMain: float32
    var maxMain: float32
    var frozen: bool
}

extension Layout {
    /// Lays out a flex container's items: rows or columns, one line or
    /// wrapped, grown and shrunk into the space, aligned. Answers the
    /// content height.
    func layoutFlex(_ box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let positionedAncestor = flow.positioned
        let s = box.Style
        let isRow = s.FlexDirection.IsRow
        let reverse = s.FlexDirection.IsReverse
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))
        let innerHeight = definiteInnerHeight(box)
        let mainAvailable: float32? = isRow ? contentWidth : innerHeight
        let crossAvailable: float32? = isRow ? innerHeight : contentWidth
        let mainGap = isRow ? s.ColumnGap.Or(0, base: contentWidth) : s.RowGap.Or(0, base: contentWidth)
        let crossGap = isRow ? s.RowGap.Or(0, base: contentWidth) : s.ColumnGap.Or(0, base: contentWidth)

        // The items, in order, with their hypothetical main sizes.
        var items: [FlexItem] = []
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                child.X = box.ContentX
                child.Y = box.ContentY
                positionedAncestor.Positioned.append(child)
                continue
            }
            resolveEdges(child, cbWidth: contentWidth)
            var basis: float32 = 0
            let cs = child.Style
            var basisLength = cs.FlexBasis
            if basisLength.IsAuto {
                basisLength = isRow ? cs.Width : cs.Height
            }
            let edgesMain = isRow ? child.Padding.Horizontal + child.Border.Horizontal : child.Padding.Vertical + child.Border.Vertical
            if let b = basisLength.Resolve(mainAvailable ?? 0), !(basisLength == .percent(0) && mainAvailable == nil) {
                basis = cs.BoxSizing == .borderBox ? b : b + edgesMain
                if case .percent = basisLength, mainAvailable == nil { basis = contentSize(child, isRow: isRow, cb: cb, flow: flow) }
            } else {
                basis = contentSize(child, isRow: isRow, cb: cb, flow: flow)
            }
            var minMain: float32 = 0
            var maxMain: float32 = 1e9
            if isRow {
                if let m = widthFromStyle(child, cs.MinWidth, cbWidth: contentWidth) { minMain = m }
                if let m = widthFromStyle(child, cs.MaxWidth, cbWidth: contentWidth) { maxMain = m }
                if cs.MinWidth == .px(0) && !cs.ClipsOverflow && child.Kind != .replaced {
                    // min-width: auto is the content's smallest width, or
                    // the given width where that is smaller.
                    let w = intrinsicWidths(child, ignoringWidth: true)
                    minMain = w.min < basis ? w.min : basis
                }
            } else {
                if let m = heightFromStyle(child, cs.MinHeight, cbHeight: innerHeight) { minMain = m }
                if let m = heightFromStyle(child, cs.MaxHeight, cbHeight: innerHeight) { maxMain = m }
            }
            if basis < minMain { basis = minMain }
            if basis > maxMain { basis = maxMain }
            items.append(FlexItem(box: child, basis: basis, main: basis, cross: 0, minMain: minMain, maxMain: maxMain, frozen: false))
        }
        if items.isEmpty { return 0 }
        sortByOrder(&items)

        // Lines.
        var lines: [[Int]] = []
        if s.FlexWrap == .nowrap || mainAvailable == nil {
            var all: [Int] = []
            var i = 0
            while i < items.count { all.append(i); i += 1 }
            lines.append(all)
        } else {
            var current: [Int] = []
            var used: float32 = 0
            var i = 0
            while i < items.count {
                let outer = items[i].basis + mainMargin(items[i].box, isRow: isRow)
                let gap = current.isEmpty ? 0 : mainGap
                if !current.isEmpty && used + gap + outer > mainAvailable! + 0.01 {
                    lines.append(current)
                    current = []
                    used = 0
                }
                current.append(i)
                used += (current.count > 1 ? mainGap : 0) + outer
                i += 1
            }
            if !current.isEmpty { lines.append(current) }
        }

        // Each line: resolve flexible lengths, then cross sizes.
        var crossOffset: float32 = 0
        var lineCrossSizes: [float32] = []
        var lineIndex = 0
        for line in lines {
            var sumOuter: float32 = 0
            for idx in line { sumOuter += items[idx].basis + mainMargin(items[idx].box, isRow: isRow) }
            let gaps = mainGap * float32(line.count > 1 ? line.count - 1 : 0)
            let space = (mainAvailable ?? (sumOuter + gaps)) - gaps
            resolveFlexibleLengths(&items, line, space: space, isRow: isRow)

            // Lay each item out at its main size to learn its cross size.
            var lineCross: float32 = 0
            for idx in line {
                let it = items[idx]
                let child = it.box
                if isRow {
                    layoutFixed(child, width: it.main, height: nil, cb: cb, flow: flow)
                    items[idx].cross = child.OuterHeight
                } else {
                    let cs = child.Style
                    var w: float32
                    if let given = widthFromStyle(child, cs.Width, cbWidth: contentWidth) {
                        w = clampWidth(child, given, cbWidth: contentWidth)
                    } else if alignFor(child, container: s) == .stretch {
                        w = contentWidth - child.Margin.Horizontal
                    } else {
                        let iw = intrinsicWidths(child)
                        w = iw.max < contentWidth - child.Margin.Horizontal ? iw.max : contentWidth - child.Margin.Horizontal
                    }
                    layoutFixed(child, width: w, height: it.main, cb: cb, flow: flow)
                    items[idx].cross = child.OuterWidth
                }
                if items[idx].cross > lineCross { lineCross = items[idx].cross }
            }
            if lines.count == 1, let ca = crossAvailable {
                lineCross = ca
            }
            lineCrossSizes.append(lineCross)

            // Main-axis placement: justify-content.
            var usedMain: float32 = gaps
            for idx in line { usedMain += items[idx].main + mainMargin(items[idx].box, isRow: isRow) }
            let free = (mainAvailable ?? usedMain) - usedMain
            var pos: float32 = 0
            var between: float32 = mainGap
            if free > 0 {
                switch s.JustifyContent {
                case .flexEnd: pos = free
                case .center: pos = free / 2
                case .spaceBetween: if line.count > 1 { between += free / float32(line.count - 1) }
                case .spaceAround:
                    let each = free / float32(line.count)
                    pos = each / 2
                    between += each
                case .spaceEvenly:
                    let each = free / float32(line.count + 1)
                    pos = each
                    between += each
                case .flexStart: pos = 0
                }
            }
            var order = line
            if reverse { order = reversed(line) }
            var k = 0
            for idx in order {
                let it = items[idx]
                let child = it.box
                let align = alignFor(child, container: s)
                var crossPos: float32 = 0
                let outerCross = it.cross
                switch align {
                case .flexEnd: crossPos = lineCross - outerCross
                case .center: crossPos = (lineCross - outerCross) / 2
                case .stretch:
                    // Stretch to the line when the cross size is auto.
                    if isRow && child.Style.Height.IsAuto {
                        layoutFixed(child, width: it.main, height: lineCross - child.Margin.Vertical, cb: cb, flow: flow)
                    } else if !isRow && child.Style.Width.IsAuto {
                        layoutFixed(child, width: lineCross - child.Margin.Horizontal, height: it.main, cb: cb, flow: flow)
                    }
                case .baseline, .flexStart, .auto: crossPos = 0
                }
                if isRow {
                    child.X = box.ContentX + pos + child.Margin.Left
                    child.Y = box.ContentY + crossOffset + crossPos + child.Margin.Top
                } else {
                    child.Y = box.ContentY + pos + child.Margin.Top
                    child.X = box.ContentX + crossOffset + crossPos + child.Margin.Left
                }
                pos += it.main + mainMargin(child, isRow: isRow) + between
                k += 1
            }
            crossOffset += lineCross + crossGap
            lineIndex += 1
        }
        let totalCross = crossOffset - (lines.isEmpty ? 0 : crossGap)

        // align-content for several lines is not distributed yet; lines
        // pack from the start.
        if isRow {
            var right: float32 = 0
            for it in items {
                if it.box.X + it.box.Width > right { right = it.box.X + it.box.Width }
            }
            box.ContentWidth = right - box.ContentX
            return totalCross
        }
        var bottom: float32 = 0
        for it in items {
            if it.box.Y + it.box.Height + it.box.Margin.Bottom > bottom { bottom = it.box.Y + it.box.Height + it.box.Margin.Bottom }
        }
        box.ContentWidth = totalCross
        return bottom - box.ContentY
    }

    /// The main size an item wants when nothing sets it: its widest
    /// content for a row, its laid-out height for a column.
    func contentSize(_ child: Box, isRow: Bool, cb: ContainingBlock, flow: Flow) -> float32 {
        if isRow {
            return intrinsicWidths(child).max
        }
        let cs = child.Style
        var w: float32 = cb.Width - child.Margin.Horizontal
        if let given = widthFromStyle(child, cs.Width, cbWidth: cb.Width) { w = given }
        layoutFixed(child, width: w, height: nil, cb: cb, flow: flow)
        return child.Height
    }

    func mainMargin(_ b: Box, isRow: Bool) -> float32 {
        return isRow ? b.Margin.Horizontal : b.Margin.Vertical
    }

    func alignFor(_ child: Box, container: ComputedStyle) -> AlignItems {
        if child.Style.AlignSelf != .auto { return child.Style.AlignSelf }
        return container.AlignItems == .auto ? .stretch : container.AlignItems
    }

    /// Grows or shrinks a line's items into the space, freezing those
    /// that hit their bounds, as the specification's loop does.
    func resolveFlexibleLengths(_ items: inout [FlexItem], _ line: [Int], space: float32, isRow: Bool) {
        var sumOuter: float32 = 0
        for idx in line {
            items[idx].main = items[idx].basis
            items[idx].frozen = false
            sumOuter += items[idx].basis + mainMargin(items[idx].box, isRow: isRow)
        }
        let growing = space > sumOuter
        // Items that cannot flex are frozen from the start.
        for idx in line {
            let f = growing ? items[idx].box.Style.FlexGrow : items[idx].box.Style.FlexShrink
            if f == 0 { items[idx].frozen = true }
        }
        var rounds = 0
        while rounds < 16 {
            rounds += 1
            var used: float32 = 0
            var totalFactor: float32 = 0
            var scaledShrink: float32 = 0
            for idx in line {
                used += items[idx].main + mainMargin(items[idx].box, isRow: isRow)
                if !items[idx].frozen {
                    if growing {
                        totalFactor += items[idx].box.Style.FlexGrow
                    } else {
                        scaledShrink += items[idx].box.Style.FlexShrink * items[idx].basis
                    }
                }
            }
            let free = space - used
            if (growing && totalFactor <= 0) || (!growing && scaledShrink <= 0) { break }
            if free > -0.01 && free < 0.01 { break }
            var violation: float32 = 0
            var clamped: [Int] = []
            for idx in line where !items[idx].frozen {
                var target: float32
                if growing {
                    target = items[idx].main + free * items[idx].box.Style.FlexGrow / totalFactor
                } else {
                    target = items[idx].main + free * (items[idx].box.Style.FlexShrink * items[idx].basis) / scaledShrink
                }
                var final = target
                if final < items[idx].minMain { final = items[idx].minMain }
                if final > items[idx].maxMain { final = items[idx].maxMain }
                violation += final - target
                if final != target { clamped.append(idx) }
                items[idx].main = final
            }
            if clamped.isEmpty { break }
            // Freeze the ones that were clamped in the violating direction.
            if violation > 0 {
                for idx in clamped where items[idx].main == items[idx].minMain { items[idx].frozen = true }
            } else if violation < 0 {
                for idx in clamped where items[idx].main == items[idx].maxMain { items[idx].frozen = true }
            } else {
                for idx in clamped { items[idx].frozen = true }
            }
        }
    }

    /// Lays out a block with its border-box width set and, when given,
    /// its height; the content decides the rest.
    func layoutFixed(_ box: Box, width: float32, height: float32?, cb: ContainingBlock, flow: Flow) {
        if box.Kind == .replaced {
            sizeReplaced(box, cb: cb)
            if let h = height { box.Height = h }
            box.Width = width
            return
        }
        box.Width = clampWidth(box, width, cbWidth: cb.Width)
        box.Positioned = []
        box.DefiniteInnerHeight = nil
        if let g = height { box.DefiniteInnerHeight = g - box.Padding.Vertical - box.Border.Vertical }
        else if let g = heightFromStyle(box, box.Style.Height, cbHeight: cb.Height) { box.DefiniteInnerHeight = g - box.Padding.Vertical - box.Border.Vertical }
        let contentHeight = layoutContent(box, flow: flow.root(box))
        var h = contentHeight + box.Padding.Vertical + box.Border.Vertical
        if let given = height {
            h = given
        } else if let given = heightFromStyle(box, box.Style.Height, cbHeight: cb.Height) {
            h = given
        }
        box.Height = clampHeight(box, h, cbHeight: cb.Height)
        box.ContentHeight = contentHeight
        if box.Style.IsPositioned {
            layoutPositioned(box, cb: ContainingBlock(width: box.PaddingBoxWidth, height: box.PaddingBoxHeight))
        }
    }

    func sortByOrder(_ items: inout [FlexItem]) {
        var i = 1
        while i < items.count {
            let it = items[i]
            var j = i - 1
            while j >= 0 && items[j].box.Style.Order > it.box.Style.Order {
                items[j + 1] = items[j]
                j -= 1
            }
            items[j + 1] = it
            i += 1
        }
    }
}

func reversed(_ list: [Int]) -> [Int] {
    var out: [Int] = []
    var i = list.count - 1
    while i >= 0 {
        out.append(list[i])
        i -= 1
    }
    return out
}
