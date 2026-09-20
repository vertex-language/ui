package webview

/// A grid item once placed: its cell range.
struct GridItem {
    var box: Box
    var column: int
    var columnSpan: int
    var row: int
    var rowSpan: int
}

extension Layout {
    /// Lays out a grid container: explicit column tracks, rows given or
    /// made as items need them, items placed where they ask or in the
    /// next free cell row by row, then sized to their cells. Answers the
    /// content height.
    func layoutGrid(_ box: Box, contentWidth: float32, flow: Flow) -> float32 {
        let s = box.Style
        let columnGap = s.ColumnGap.Or(0, base: contentWidth)
        let rowGap = s.RowGap.Or(0, base: contentWidth)
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(box))

        // The items, in order.
        var boxes: [Box] = []
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed {
                child.X = box.ContentX
                child.Y = box.ContentY
                flow.positioned.Positioned.append(child)
                continue
            }
            resolveEdges(child, cbWidth: contentWidth)
            boxes.append(child)
        }

        // Column tracks: the template's, with auto-fill repeats counted
        // to fit, or one auto column for a grid without a template.
        var columns = expandAutoFill(s.GridColumns, available: contentWidth, gap: columnGap)
        if columns.isEmpty { columns = [.auto] }
        var maxColumnNeeded = 1
        for b in boxes {
            let p = b.Style.GridColumn
            let end = (p.Start > 0 ? int(p.Start) : 1) + int(p.Span) - 1
            if end > maxColumnNeeded { maxColumnNeeded = end }
        }
        while columns.count < maxColumnNeeded { columns.append(.auto) }
        let columnCount = columns.count

        // Placement: explicit positions first, then the rest row by row.
        var items: [GridItem] = []
        var occupied: [[Bool]] = []
        func occupy(_ r: int, _ c: int) {
            while occupied.count <= r { occupied.append([Bool](repeating: false, count: columnCount)) }
            if c < columnCount { occupied[r][c] = true }
        }
        func isFree(_ r: int, _ c: int, _ rs: int, _ cs: int) -> Bool {
            var rr = r
            while rr < r + rs {
                var cc = c
                while cc < c + cs {
                    if cc >= columnCount { return false }
                    if rr < occupied.count && occupied[rr][cc] { return false }
                    cc += 1
                }
                rr += 1
            }
            return true
        }
        var pending: [Box] = []
        for b in boxes {
            let pc = b.Style.GridColumn
            let pr = b.Style.GridRow
            let cs = pc.Span > 0 ? int(pc.Span) : 1
            let rs = pr.Span > 0 ? int(pr.Span) : 1
            if pc.Start > 0 && pr.Start > 0 {
                let item = GridItem(box: b, column: int(pc.Start) - 1, columnSpan: cs, row: int(pr.Start) - 1, rowSpan: rs)
                items.append(item)
                var rr = item.row
                while rr < item.row + rs { var cc = item.column; while cc < item.column + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
            } else {
                pending.append(b)
            }
        }
        var cursorRow = 0
        var cursorColumn = 0
        for b in pending {
            let pc = b.Style.GridColumn
            let pr = b.Style.GridRow
            var cs = pc.Span > 0 ? int(pc.Span) : 1
            let rs = pr.Span > 0 ? int(pr.Span) : 1
            if cs > columnCount { cs = columnCount }
            var placed = false
            if pc.Start > 0 {
                // A fixed column: the first row where it is free.
                let c = int(pc.Start) - 1
                var r = 0
                while r < 10000 {
                    if isFree(r, c, rs, cs) {
                        items.append(GridItem(box: b, column: c, columnSpan: cs, row: r, rowSpan: rs))
                        var rr = r
                        while rr < r + rs { var cc = c; while cc < c + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
                        placed = true
                        break
                    }
                    r += 1
                }
            }
            if placed { continue }
            var guardRounds = 0
            while guardRounds < 100000 {
                guardRounds += 1
                if cursorColumn + cs > columnCount {
                    cursorRow += 1
                    cursorColumn = 0
                }
                if isFree(cursorRow, cursorColumn, rs, cs) {
                    items.append(GridItem(box: b, column: cursorColumn, columnSpan: cs, row: cursorRow, rowSpan: rs))
                    var rr = cursorRow
                    while rr < cursorRow + rs { var cc = cursorColumn; while cc < cursorColumn + cs { occupy(rr, cc); cc += 1 }; rr += 1 }
                    cursorColumn += cs
                    break
                }
                cursorColumn += 1
            }
        }
        var rowCount = occupied.count
        for it in items where it.row + it.rowSpan > rowCount { rowCount = it.row + it.rowSpan }
        if rowCount == 0 { return 0 }

        // Column widths: fixed tracks first, auto tracks from what their
        // items need, then fr tracks share the rest.
        let gaps = columnGap * float32(columnCount > 1 ? columnCount - 1 : 0)
        var widths = [float32](repeating: 0, count: columnCount)
        var frs = [float32](repeating: 0, count: columnCount)
        var totalFr: float32 = 0
        var fixed: float32 = 0
        var c = 0
        while c < columnCount {
            switch columns[c] {
            case .length(let l):
                widths[c] = l.Or(0, base: contentWidth)
                fixed += widths[c]
            case .fr(let f):
                frs[c] = f > 0 ? f : 1
                totalFr += frs[c]
            case .auto:
                var need: float32 = 0
                for it in items where it.column == c && it.columnSpan == 1 {
                    let w = intrinsicWidths(it.box)
                    let outer = w.max + it.box.Margin.Horizontal
                    if outer > need { need = outer }
                }
                widths[c] = need
                fixed += need
            case .minmax(let minPx, let maxPx, let maxFr):
                if maxFr > 0 {
                    frs[c] = maxFr
                    totalFr += maxFr
                    widths[c] = minPx
                } else {
                    var need = minPx
                    for it in items where it.column == c && it.columnSpan == 1 {
                        let w = intrinsicWidths(it.box)
                        if w.max + it.box.Margin.Horizontal > need { need = w.max + it.box.Margin.Horizontal }
                    }
                    if maxPx > 0 && need > maxPx { need = maxPx }
                    widths[c] = need
                    fixed += need
                }
            }
            c += 1
        }
        var free = contentWidth - gaps - fixed
        if totalFr > 0 {
            // Each fr track gets its share, no less than its minimum.
            var share = free > 0 ? free / totalFr : 0
            var rounds = 0
            while rounds < 8 {
                rounds += 1
                var overMin: float32 = 0
                var frLeft: float32 = 0
                c = 0
                while c < columnCount {
                    if frs[c] > 0 {
                        let got = share * frs[c]
                        if got < widths[c] { overMin += widths[c] } else { frLeft += frs[c] }
                    }
                    c += 1
                }
                let newShare = frLeft > 0 ? (free - overMin) / frLeft : share
                if newShare == share || frLeft == 0 { break }
                share = newShare
            }
            c = 0
            while c < columnCount {
                if frs[c] > 0 {
                    let got = share * frs[c]
                    if got > widths[c] { widths[c] = got }
                }
                c += 1
            }
        } else if free > 0 && s.JustifyContent == .flexStart {
            // Auto tracks with room left take it, in proportion.
            var autoTotal: float32 = 0
            c = 0
            while c < columnCount {
                if case .auto = columns[c] { autoTotal += widths[c] > 0 ? widths[c] : 1 }
                c += 1
            }
            if autoTotal > 0 {
                c = 0
                while c < columnCount {
                    if case .auto = columns[c] { widths[c] += free * (widths[c] > 0 ? widths[c] : 1) / autoTotal }
                    c += 1
                }
            }
        }
        _ = free
        var columnX = [float32](repeating: 0, count: columnCount + 1)
        var columnEnd = [float32](repeating: 0, count: columnCount)
        c = 0
        var x: float32 = 0
        while c < columnCount {
            columnX[c] = x
            columnEnd[c] = x + widths[c]
            x += widths[c] + columnGap
            c += 1
        }
        columnX[columnCount] = x - columnGap

        // Row heights: given tracks, else the tallest item in the row
        // once laid out at its column width.
        var heights = [float32](repeating: 0, count: rowCount)
        var r = 0
        while r < rowCount {
            let track: GridTrack = r < s.GridRows.count ? s.GridRows[r] : s.GridAutoRows
            if case .length(let l) = track, let h = l.Resolve(cb.Height ?? 0) { heights[r] = h }
            if case .minmax(let minPx, _, _) = track { heights[r] = minPx }
            r += 1
        }
        for it in items {
            let w = columnEnd[it.column + it.columnSpan - 1] - columnX[it.column] - it.box.Margin.Horizontal
            let child = it.box
            var itemWidth = w
            if let given = widthFromStyle(child, child.Style.Width, cbWidth: w) {
                itemWidth = clampWidth(child, given, cbWidth: w)
            } else if alignFor(child, container: s) != .stretch && s.AlignItems != .auto && false {
                itemWidth = w
            }
            layoutFixed(child, width: itemWidth, height: nil, cb: ContainingBlock(width: w, height: nil), flow: flow.root(child))
            if it.rowSpan == 1 {
                let track: GridTrack = it.row < s.GridRows.count ? s.GridRows[it.row] : s.GridAutoRows
                var fixedRow = false
                if case .length = track { fixedRow = true }
                if !fixedRow && child.OuterHeight > heights[it.row] { heights[it.row] = child.OuterHeight }
            }
        }
        var rowY = [float32](repeating: 0, count: rowCount + 1)
        var rowEnd = [float32](repeating: 0, count: rowCount)
        var y: float32 = 0
        r = 0
        while r < rowCount {
            rowY[r] = y
            rowEnd[r] = y + heights[r]
            y += heights[r] + rowGap
            r += 1
        }
        rowY[rowCount] = y - rowGap

        // Place and stretch.
        for it in items {
            let child = it.box
            let cellX = columnX[it.column]
            let cellY = rowY[it.row]
            let cellW = columnEnd[it.column + it.columnSpan - 1] - cellX
            let cellH = rowEnd[it.row + it.rowSpan - 1] - cellY
            let align = alignFor(child, container: s)
            if align == .stretch && child.Style.Height.IsAuto && child.OuterHeight < cellH {
                layoutFixed(child, width: child.Width, height: cellH - child.Margin.Vertical, cb: ContainingBlock(width: cellW, height: cellH), flow: flow.root(child))
            }
            var dy: float32 = 0
            if align == .center { dy = (cellH - child.OuterHeight) / 2 } else if align == .flexEnd { dy = cellH - child.OuterHeight }
            var dx: float32 = 0
            if child.Width + child.Margin.Horizontal < cellW {
                switch s.JustifyContent {
                case .center: dx = (cellW - child.OuterWidth) / 2
                case .flexEnd: dx = cellW - child.OuterWidth
                default: dx = 0
                }
            }
            child.X = box.ContentX + cellX + child.Margin.Left + dx
            child.Y = box.ContentY + cellY + child.Margin.Top + dy
        }
        box.ContentWidth = columnX[columnCount]
        return rowY[rowCount]
    }

    /// Tracks with a repeat(auto-fill) expanded to as many as fit.
    func expandAutoFill(_ tracks: [GridTrack], available: float32, gap: float32) -> [GridTrack] {
        var marker = -1
        var i = 0
        while i < tracks.count {
            if case .fr(let f) = tracks[i], f < 0 { marker = i }
            i += 1
        }
        if marker < 0 { return tracks }
        // The tracks before the marker repeat; their widths are their
        // minimums.
        var unit: float32 = 0
        var pattern: [GridTrack] = []
        i = 0
        while i < marker {
            pattern.append(tracks[i])
            switch tracks[i] {
            case .length(let l): unit += l.Or(0, base: available)
            case .minmax(let minPx, _, _): unit += minPx
            default: unit += 0
            }
            i += 1
        }
        if unit <= 0 || pattern.isEmpty { return pattern }
        var count = int((available + gap) / (unit + gap * float32(pattern.count)))
        if count < 1 { count = 1 }
        var out: [GridTrack] = []
        var k = 0
        while k < count {
            for t in pattern { out.append(t) }
            k += 1
        }
        i = marker + 1
        while i < tracks.count { out.append(tracks[i]); i += 1 }
        return out
    }
}
