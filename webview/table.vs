package webview

import "ui/draw"

/// A cell in a table's grid, with the columns it spans.
struct GridCell {
    var box: Box
    var column: int
    var span: int
    var rowSpan: int
}

/// A table's rows and columns, gathered from its boxes.
struct TableGrid {
    var captions: [Box] = []
    var rows: [[GridCell]] = []
    var rowBoxes: [Box] = []
    var groupOf: [Box?] = []
    var columns: int = 0
}

extension Layout {
    /// Gathers a table's rows, in order, through its row groups.
    func gridOf(_ table: Box) -> TableGrid {
        var grid = TableGrid()
        for child in table.Children {
            switch child.Style.Display {
            case .tableCaption:
                grid.captions.append(child)
            case .tableRow:
                addRow(child, group: nil, to: &grid)
            case .tableRowGroup, .tableHeaderGroup, .tableFooterGroup:
                for row in child.Children where row.Style.Display == .tableRow {
                    addRow(row, group: child, to: &grid)
                }
            default:
                if child.Kind == .block && !child.IsAnonymous {
                    // A cell or block dropped straight in a table: its own row.
                    addRow(child, group: nil, to: &grid, wrapAsCell: true)
                }
            }
        }
        return grid
    }

    func addRow(_ row: Box, group: Box?, to grid: inout TableGrid, wrapAsCell: Bool = false) {
        var cells: [GridCell] = []
        var column = 0
        if wrapAsCell {
            cells.append(GridCell(box: row, column: 0, span: 1, rowSpan: 1))
            column = 1
        } else {
            for cell in row.Children where cell.Style.Display == .tableCell || (cell.Kind == .block && !cell.IsAnonymous) {
                var span = 1
                var rowSpan = 1
                if let n = cell.Node {
                    if let cs = n.GetAttribute("colspan") {
                        let b = [uint8](cs.utf8)
                        let v = int(draw.parseNumber(b, 0, b.count))
                        if v > 1 { span = v }
                    }
                    if let rs = n.GetAttribute("rowspan") {
                        let b = [uint8](rs.utf8)
                        let v = int(draw.parseNumber(b, 0, b.count))
                        if v > 1 { rowSpan = v }
                    }
                }
                cells.append(GridCell(box: cell, column: column, span: span, rowSpan: rowSpan))
                column += span
            }
        }
        if column > grid.columns { grid.columns = column }
        grid.rows.append(cells)
        grid.rowBoxes.append(row)
        grid.groupOf.append(group)
    }

    /// The narrowest and widest each column can be, from its cells.
    func columnLimits(_ grid: TableGrid, cbWidth: float32) -> (min: [float32], max: [float32]) {
        var mins = [float32](repeating: 0, count: grid.columns)
        var maxs = [float32](repeating: 0, count: grid.columns)
        for row in grid.rows {
            for cell in row {
                resolveEdges(cell.box, cbWidth: cbWidth)
                var w = intrinsicWidths(cell.box)
                if let given = widthFromStyle(cell.box, cell.box.Style.Width, cbWidth: cbWidth) {
                    if given > w.min { w.max = given } else { w.max = w.min }
                    if given > w.min { w.min = given }
                }
                let each = float32(cell.span)
                var c = 0
                while c < cell.span && cell.column + c < grid.columns {
                    let i = cell.column + c
                    if w.min / each > mins[i] { mins[i] = w.min / each }
                    if w.max / each > maxs[i] { maxs[i] = w.max / each }
                    c += 1
                }
            }
        }
        var i = 0
        while i < grid.columns {
            if maxs[i] < mins[i] { maxs[i] = mins[i] }
            i += 1
        }
        return (min: mins, max: maxs)
    }

    /// The widths a table wants: its columns' limits plus the spacing.
    func tableIntrinsicWidths(_ table: Box) -> (min: float32, max: float32) {
        let grid = gridOf(table)
        if grid.columns == 0 { return (min: 0, max: 0) }
        let limits = columnLimits(grid, cbWidth: 0)
        let spacing = table.Style.BorderCollapse == .collapse ? 0 : table.Style.BorderSpacing
        var minW = spacing
        var maxW = spacing
        var i = 0
        while i < grid.columns {
            minW += limits.min[i] + spacing
            maxW += limits.max[i] + spacing
            i += 1
        }
        return (min: minW, max: maxW)
    }

    /// Lays out a table's rows and cells in the width the table has, and
    /// answers the content height.
    func layoutTable(_ table: Box, contentWidth: float32, flow: Flow) -> float32 {
        let grid = gridOf(table)
        let spacing = table.Style.BorderCollapse == .collapse ? 0 : table.Style.BorderSpacing
        var y: float32 = 0
        let cb = ContainingBlock(width: contentWidth, height: definiteInnerHeight(table))

        // Captions come first, as blocks.
        for caption in grid.captions {
            layoutBlock(caption, cb: cb, flow: flow.root(caption))
            caption.X = table.ContentX + caption.Margin.Left
            caption.Y = table.ContentY + y + caption.Margin.Top
            y += caption.OuterHeight
        }
        if grid.columns == 0 { return y }

        // Column widths: the limits stretched or squeezed into the width.
        let limits = columnLimits(grid, cbWidth: contentWidth)
        let available = contentWidth - spacing * float32(grid.columns + 1)
        var sumMin: float32 = 0
        var sumMax: float32 = 0
        var i = 0
        while i < grid.columns {
            sumMin += limits.min[i]
            sumMax += limits.max[i]
            i += 1
        }
        var widths = [float32](repeating: 0, count: grid.columns)
        i = 0
        if available >= sumMax {
            // Room to spare: every column gets its widest, and the rest
            // is shared in proportion.
            let extra = available - sumMax
            while i < grid.columns {
                widths[i] = limits.max[i] + (sumMax > 0 ? extra * limits.max[i] / sumMax : extra / float32(grid.columns))
                i += 1
            }
        } else if available <= sumMin {
            while i < grid.columns {
                widths[i] = limits.min[i]
                i += 1
            }
        } else {
            let t = (available - sumMin) / (sumMax - sumMin > 0 ? sumMax - sumMin : 1)
            while i < grid.columns {
                widths[i] = limits.min[i] + (limits.max[i] - limits.min[i]) * t
                i += 1
            }
        }

        // Rows: each cell at its columns' width, the row as tall as its
        // tallest cell, cells stretched to the row.
        var r = 0
        var previousGroup: Box? = nil
        var groupTop: float32 = 0
        y += spacing
        while r < grid.rows.count {
            let rowBox = grid.rowBoxes[r]
            let group = grid.groupOf[r]
            if group?.Id != previousGroup?.Id {
                if let g = previousGroup {
                    g.Height = y - groupTop
                    g.ContentHeight = g.Height
                }
                if let g = group {
                    g.X = table.ContentX
                    g.Y = table.ContentY + y - spacing
                    g.Width = contentWidth
                    g.Margin = draw.Edges.zero
                    g.Padding = draw.Edges.zero
                    g.Border = draw.Edges.zero
                    g.Positioned = []
                    groupTop = y - spacing
                }
                previousGroup = group
            }
            var rowHeight: float32 = 0
            if let given = heightFromStyle(rowBox, rowBox.Style.Height, cbHeight: nil) { rowHeight = given }
            for cell in grid.rows[r] {
                var w: float32 = 0
                var c = 0
                while c < cell.span && cell.column + c < grid.columns {
                    w += widths[cell.column + c]
                    if c > 0 { w += spacing }
                    c += 1
                }
                let b = cell.box
                resolveEdges(b, cbWidth: contentWidth)
                b.Margin = draw.Edges.zero
                if table.Style.BorderCollapse == .collapse {
                    // Collapsed borders: neighbours share one edge, so a
                    // cell draws only its right and bottom, and the
                    // first row and column their top and left.
                    if r > 0 { b.Border.Top = 0 }
                    if cell.column > 0 { b.Border.Left = 0 }
                }
                layoutFixed(b, width: w, height: nil, cb: ContainingBlock(width: w, height: nil), flow: flow.root(b))
                if b.Height > rowHeight { rowHeight = b.Height }
            }
            for cell in grid.rows[r] {
                let b = cell.box
                var start: float32 = spacing
                var k = 0
                while k < cell.column {
                    start += widths[k] + spacing
                    k += 1
                }
                b.X = start
                b.Y = 0
                if b.Height < rowHeight {
                    let extra = rowHeight - b.Height
                    let align = b.Style.VerticalAlign
                    var shift: float32 = 0
                    if align == .middle { shift = extra / 2 } else if align == .bottom { shift = extra }
                    if shift > 0 { shiftContent(b, by: shift) }
                    b.Height = rowHeight
                }
            }
            let rowY = table.ContentY + y
            rowBox.X = table.ContentX
            rowBox.Y = rowY
            if let g = group {
                rowBox.X = 0
                rowBox.Y = rowY - g.Y
            }
            rowBox.Width = contentWidth
            rowBox.Height = rowHeight
            rowBox.Margin = draw.Edges.zero
            rowBox.Padding = draw.Edges.zero
            rowBox.Border = draw.Edges.zero
            rowBox.Positioned = []
            rowBox.Lines = []
            y += rowHeight + spacing
            r += 1
        }
        if let g = previousGroup {
            g.Height = y - groupTop
            g.ContentHeight = g.Height
        }
        table.ContentWidth = contentWidth
        return y
    }

    /// Moves a box's content down inside it: for vertical-align in a
    /// cell taller than what it holds.
    func shiftContent(_ box: Box, by dy: float32) {
        var i = 0
        while i < box.Lines.count {
            box.Lines[i].Y += dy
            var f = 0
            while f < box.Lines[i].Fragments.count {
                box.Lines[i].Fragments[f].Y += dy
                if box.Lines[i].Fragments[f].Kind == .atomic {
                    box.Lines[i].Fragments[f].Box.Y += dy
                }
                f += 1
            }
            var s = 0
            while s < box.Lines[i].Spans.count {
                box.Lines[i].Spans[s].Y += dy
                s += 1
            }
            i += 1
        }
        if box.Lines.isEmpty {
            for child in box.Children where child.Kind == .block {
                child.Y += dy
            }
        }
    }
}
