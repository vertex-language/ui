package webview

import "text/html"
import "ui/draw"

/// What lies under a point: the deepest box, the element it belongs
/// to, and for text, where in the text.
public struct Hit {
    public var Box: Box
    public var Node: html.Node?
    /// The text box hit, if the point was on text.
    public var TextBox: Box?
    /// Where in the text box's text the point falls, in bytes.
    public var TextOffset: int
    /// The box's border-box corner in page coordinates.
    public var PageX: float32
    public var PageY: float32
}

/// The innermost box under a page point.
func hitTest(_ box: Box, _ px: float32, _ py: float32, originX: float32, originY: float32) -> Hit? {
    let x = originX + box.X + box.OffsetX
    let y = originY + box.Y + box.OffsetY
    let inside = px >= x && py >= y && px < x + box.Width && py < y + box.Height
    let sx = x - box.ScrollX
    let sy = y - box.ScrollY

    // Positioned boxes are on top, the highest z-index first.
    if !box.Positioned.isEmpty {
        var i = box.Positioned.count - 1
        var best: Hit? = nil
        var bestZ: int32 = -2147483647
        while i >= 0 {
            let p = box.Positioned[i]
            if let h = hitTest(p, px, py, originX: sx, originY: sy) {
                if best == nil || p.Style.ZIndex >= bestZ {
                    best = h
                    bestZ = p.Style.ZIndex
                }
            }
            i -= 1
        }
        if let h = best { return h }
    }
    if box.Style.ClipsOverflow && !inside { return nil }

    if box.Kind == .replaced {
        return inside ? Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y) : nil
    }
    if !box.Lines.isEmpty {
        var li = box.Lines.count - 1
        while li >= 0 {
            let line = box.Lines[li]
            let lineTop = sy + line.Y
            if py >= lineTop && py < lineTop + line.Height {
                var fi = line.Fragments.count - 1
                while fi >= 0 {
                    let f = line.Fragments[fi]
                    let fx = sx + f.X
                    let fy = sy + f.Y
                    if px >= fx && px < fx + f.Width {
                        if f.Kind == .atomic {
                            if let h = hitTest(f.Box, px, py, originX: sx, originY: sy) { return h }
                        } else if f.Kind == .text && py >= fy - 2 && py < fy + f.Height + 2 {
                            let offset = f.Offset + offsetInRun(f, at: px - fx, letterSpacing: f.Owner.Style.LetterSpacing)
                            return Hit(Box: f.Owner, Node: f.Owner.Element, TextBox: f.Box, TextOffset: offset, PageX: fx, PageY: fy)
                        }
                    }
                    fi -= 1
                }
                // On the line but beside its text: the inline element
                // whose span covers the point, else the container.
                var si = line.Spans.count - 1
                while si >= 0 {
                    let sp = line.Spans[si]
                    if px >= sx + sp.X && px < sx + sp.X + sp.Width {
                        return Hit(Box: sp.Box, Node: sp.Box.Element, TextBox: nil, TextOffset: 0, PageX: sx + sp.X, PageY: sy + sp.Y)
                    }
                    si -= 1
                }
                if inside {
                    return Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y)
                }
            }
            li -= 1
        }
    } else {
        var i = box.Children.count - 1
        while i >= 0 {
            let c = box.Children[i]
            i -= 1
            if c.Style.Position == .absolute || c.Style.Position == .fixed { continue }
            if c.Kind == .text || c.Kind == .inline || c.Kind == .lineBreak { continue }
            if let h = hitTest(c, px, py, originX: sx, originY: sy) { return h }
        }
    }
    if inside {
        return Hit(Box: box, Node: box.Element, TextBox: nil, TextOffset: 0, PageX: x, PageY: y)
    }
    return nil
}

/// The byte offset in a text fragment nearest a horizontal position:
/// glyph by glyph, rounding to the nearer edge.
func offsetInRun(_ f: Fragment, at x: float32, letterSpacing: float32) -> int {
    let bytes = [uint8](f.Text.utf8)
    // Glyphs and bytes line up only for ASCII; for anything else the
    // run is measured by prefix.
    var ascii = true
    for b in bytes where b >= 128 { ascii = false }
    if ascii && f.Run.Count == bytes.count {
        var pen: float32 = 0
        var i = 0
        while i < f.Run.Count {
            let adv = f.Run.Advances[i] + letterSpacing
            if x < pen + adv / 2 { return i }
            pen += adv
            i += 1
        }
        return bytes.count
    }
    let face = f.Owner.Style.Face
    var best = 0
    var bestDist: float32 = 1e9
    var i = 0
    while i <= bytes.count {
        if i == bytes.count || (bytes[i] & 0xC0) != 0x80 {
            let w = face.Measure(draw.stringOf(bytes, 0, i))
            let d = w > x ? w - x : x - w
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        i += 1
    }
    return best
}

/// The page position of a box: its corner with every ancestor's added.
func pagePosition(_ box: Box) -> (x: float32, y: float32) {
    var x: float32 = 0
    var y: float32 = 0
    var cur: Box? = box
    while let b = cur {
        x += b.X + b.OffsetX
        y += b.Y + b.OffsetY
        if let p = b.Parent {
            x -= p.ScrollX
            y -= p.ScrollY
        }
        cur = b.Parent
    }
    return (x: x, y: y)
}
