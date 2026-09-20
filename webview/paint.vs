package webview

import "ui/draw"
import "ui/font"

public enum PaintKind: Equatable {
    case fill
    case border
    case text
    case image
    case clip
    case unclip
}

/// One thing to paint, in CSS pixels on the page: a filled rectangle, a
/// border, a run of text at a baseline, an image, or a change of clip.
public struct PaintItem {
    public var Kind: PaintKind
    public var Rect: draw.Rect
    public var Color: draw.Color
    public var Radii: draw.Radii
    /// A border's widths and its four colors.
    public var Widths: draw.Edges
    public var Colors: [draw.Color]
    /// Text: the pen's start and baseline, the run, and letter-spacing.
    public var X: float32
    public var Y: float32
    public var Run: font.Run
    public var LetterSpacing: float32
    public var Image: draw.Image?
    public var Opacity: float32

    init(_ kind: PaintKind) {
        Kind = kind
        Rect = draw.Rect.zero
        Color = draw.Color.transparent
        Radii = draw.Radii.zero
        Widths = draw.Edges.zero
        Colors = []
        X = 0
        Y = 0
        Run = font.Run()
        LetterSpacing = 0
        Image = nil
        Opacity = 1
    }

    static func fill(_ r: draw.Rect, _ c: draw.Color, _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.fill)
        it.Rect = r
        it.Color = c
        it.Radii = radii
        return it
    }

    static func border(_ r: draw.Rect, _ widths: draw.Edges, _ colors: [draw.Color], _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.border)
        it.Rect = r
        it.Widths = widths
        it.Colors = colors
        it.Radii = radii
        return it
    }

    static func text(_ x: float32, _ baseline: float32, _ run: font.Run, _ c: draw.Color, _ letterSpacing: float32) -> PaintItem {
        var it = PaintItem(.text)
        it.X = x
        it.Y = baseline
        it.Run = run
        it.Color = c
        it.LetterSpacing = letterSpacing
        return it
    }

    static func image(_ r: draw.Rect, _ img: draw.Image, _ opacity: float32) -> PaintItem {
        var it = PaintItem(.image)
        it.Rect = r
        it.Image = img
        it.Opacity = opacity
        return it
    }

    static func clip(_ r: draw.Rect) -> PaintItem {
        var it = PaintItem(.clip)
        it.Rect = r
        return it
    }

    static let unclip = PaintItem(.unclip)
}

enum PaintPhase: Equatable {
    case blockBackgrounds
    case floats
    case inlineContent
}

/// Builds the list of what to paint from a laid-out box tree, in the
/// order CSS paints: block backgrounds and borders, then floats, then
/// inline content, with positioned boxes after their siblings.
final class DisplayListBuilder {
    var items: [PaintItem] = []
    /// The page's state the painter needs.
    var focused: int64 = 0
    var caret: int = -1
    var caretVisible: bool = true
    var opacity: float32 = 1

    init() {}

    func build(_ root: Box, viewportWidth: float32, viewportHeight: float32, background: draw.Color) -> [PaintItem] {
        items = []
        // The canvas takes the root's background, or the body's where the
        // root has none, over the whole viewport.
        var canvasColor = background
        var skipBackgroundOf: Int = 0
        if root.Style.BackgroundColor.A > 0 {
            canvasColor = root.Style.BackgroundColor
            skipBackgroundOf = root.Id
        } else {
            for c in root.Children where c.Node?.TagName == "body" {
                if c.Style.BackgroundColor.A > 0 {
                    canvasColor = c.Style.BackgroundColor
                    skipBackgroundOf = c.Id
                }
            }
        }
        if canvasColor.A > 0 {
            let h = viewportHeight > root.Y + root.Height + root.Margin.Bottom ? viewportHeight : root.Y + root.Height + root.Margin.Bottom
            items.append(.fill(draw.Rect(0, 0, viewportWidth, h), canvasColor, draw.Radii.zero))
        }
        paintBox(root, x: 0, y: 0, skipBackground: skipBackgroundOf)
        return items
    }

    /// Paints a box as CSS orders a stacking context: the backgrounds
    /// and borders of it and its in-flow block descendants, then its
    /// floats, then its inline content and replaced content, then the
    /// boxes positioned against it.
    func paintBox(_ box: Box, x parentX: float32, y parentY: float32, skipBackground: Int) {
        let s = box.Style
        if s.Visibility != .visible && !hasVisibleDescendant(box) { return }
        let x = parentX + box.X + box.OffsetX
        let y = parentY + box.Y + box.OffsetY
        let savedOpacity = opacity
        if s.Opacity < 1 { opacity = opacity * s.Opacity }
        let clips = s.ClipsOverflow
        if clips {
            paintBackgroundAndBorderIfVisible(box, x: x, y: y, skipBackground: skipBackground)
            items.append(.clip(draw.Rect(x + box.Border.Left, y + box.Border.Top, box.PaddingBoxWidth, box.PaddingBoxHeight)))
            paintPhase(box, .blockBackgrounds, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: true)
        } else {
            paintPhase(box, .blockBackgrounds, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        }
        paintPhase(box, .floats, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        paintPhase(box, .inlineContent, x: parentX, y: parentY, skipBackground: skipBackground, isRoot: false)
        let sx = x - box.ScrollX
        let sy = y - box.ScrollY
        if !box.Positioned.isEmpty {
            var list = box.Positioned
            sortByZIndex(&list)
            for p in list {
                paintBox(p, x: sx, y: sy, skipBackground: skipBackground)
            }
        }
        if clips {
            items.append(PaintItem.unclip)
        }
        if s.Visibility == .visible && s.OutlineWidth > 0 && box.Node != nil && box.Node!.Id == focused {
            let w = s.OutlineWidth
            let ring = draw.Rect(x - w, y - w, box.Width + 2 * w, box.Height + 2 * w)
            let c = color(s.OutlineColor ?? draw.Color(0, 95, 204))
            items.append(.border(ring, draw.Edges(all: w), [c, c, c, c], s.BorderRadius.IsZero ? draw.Radii.zero : draw.Radii(all: s.BorderRadius.TopLeft + w)))
        }
        opacity = savedOpacity
    }

    func paintBackgroundAndBorderIfVisible(_ box: Box, x: float32, y: float32, skipBackground: Int) {
        if box.Style.Visibility == .visible && box.Id != skipBackground {
            paintBackgroundAndBorder(box, x: x, y: y)
        }
    }

    /// One phase of a box and its in-flow descendants. Descendants that
    /// start a stacking context of their own -- positioned boxes,
    /// floats, atomic inlines -- are painted whole in the phase that
    /// owns them, and skipped in the others.
    func paintPhase(_ box: Box, _ phase: PaintPhase, x parentX: float32, y parentY: float32, skipBackground: Int, isRoot: Bool) {
        let s = box.Style
        let x = parentX + box.X + box.OffsetX
        let y = parentY + box.Y + box.OffsetY
        let visible = s.Visibility == .visible
        if phase == .blockBackgrounds && !isRoot {
            paintBackgroundAndBorderIfVisible(box, x: x, y: y, skipBackground: skipBackground)
        }
        let sx = x - box.ScrollX
        let sy = y - box.ScrollY
        if box.Kind == .replaced {
            if phase == .inlineContent && visible { paintReplaced(box, x: x, y: y) }
            return
        }
        if !box.Lines.isEmpty {
            // Floats among the lines belong to the float phase; the
            // lines themselves to the inline phase.
            if phase == .floats {
                for child in box.Children {
                    paintFloatsWithin(child, x: sx, y: sy, skipBackground: skipBackground)
                }
            } else if phase == .inlineContent {
                for line in box.Lines {
                    paintLine(box, line, x: sx, y: sy, visible: visible)
                }
            }
            return
        }
        for child in box.Children {
            if child.Style.Position == .absolute || child.Style.Position == .fixed { continue }
            if child.Kind == .text || child.Kind == .inline || child.Kind == .lineBreak { continue }
            if child.Style.Float != .none {
                if phase == .floats { paintBox(child, x: sx, y: sy, skipBackground: skipBackground) }
                continue
            }
            if child.Style.ClipsOverflow || child.Style.Opacity < 1 {
                // A clipping or translucent box paints as a whole, in
                // the phase its background would go in.
                if phase == .blockBackgrounds { paintBox(child, x: sx, y: sy, skipBackground: skipBackground) }
                continue
            }
            paintPhase(child, phase, x: sx, y: sy, skipBackground: skipBackground, isRoot: false)
        }
    }

    /// Floats that inline layout placed among a box's inline content.
    func paintFloatsWithin(_ box: Box, x: float32, y: float32, skipBackground: Int) {
        if box.Kind == .text || box.Kind == .lineBreak { return }
        if box.Style.Float != .none {
            paintBox(box, x: x, y: y, skipBackground: skipBackground)
            return
        }
        if box.Kind == .inline {
            for child in box.Children {
                paintFloatsWithin(child, x: x, y: y, skipBackground: skipBackground)
            }
        }
    }

    func color(_ c: draw.Color) -> draw.Color {
        return opacity < 1 ? c.Faded(opacity) : c
    }

    func hasVisibleDescendant(_ box: Box) -> bool {
        for c in box.Children {
            if c.Style.Visibility == .visible || hasVisibleDescendant(c) { return true }
        }
        return false
    }

    func paintBackgroundAndBorder(_ box: Box, x: float32, y: float32) {
        let s = box.Style
        let rect = draw.Rect(x, y, box.Width, box.Height)
        var radii = s.BorderRadius
        if !radii.IsZero { radii = radii.Fitted(box.Width, box.Height) }
        if s.BackgroundColor.A > 0 {
            items.append(.fill(rect, color(s.BackgroundColor), radii))
        }
        let widths = box.Border
        if widths.Top > 0 || widths.Right > 0 || widths.Bottom > 0 || widths.Left > 0 {
            var colors: [draw.Color] = []
            var side = 0
            while side < 4 {
                colors.append(color(borderSideColor(s, side)))
                side += 1
            }
            items.append(.border(rect, widths, colors, radii))
        }
    }

    /// A side's color, with inset, outset, groove and ridge shaded the
    /// way browsers shade them: top and left light for outset, dark for
    /// inset.
    func borderSideColor(_ s: ComputedStyle, _ side: Int) -> draw.Color {
        let base = s.BorderColor(side)
        var style = s.BorderTopStyle
        if side == 1 { style = s.BorderRightStyle } else if side == 2 { style = s.BorderBottomStyle } else if side == 3 { style = s.BorderLeftStyle }
        let topLeft = side == 0 || side == 3
        switch style {
        case .inset: return topLeft ? shade(base, 0.6) : shade(base, 1.0)
        case .outset: return topLeft ? shade(base, 1.0) : shade(base, 0.6)
        case .groove: return topLeft ? shade(base, 0.6) : shade(base, 1.0)
        case .ridge: return topLeft ? shade(base, 1.0) : shade(base, 0.6)
        default: return base
        }
    }

    func shade(_ c: draw.Color, _ f: float32) -> draw.Color {
        if f >= 1 { return c }
        return draw.Color(uint8(float32(c.R) * f), uint8(float32(c.G) * f), uint8(float32(c.B) * f), c.A)
    }

    func paintLine(_ container: Box, _ line: Line, x: float32, y: float32, visible: Bool) {
        // Inline elements' backgrounds and borders, outer first.
        for sp in line.Spans {
            let b = sp.Box
            let s = b.Style
            if b.Style.Visibility != .visible { continue }
            let rect = draw.Rect(x + sp.X, y + sp.Y, sp.Width, sp.Height)
            if s.BackgroundColor.A > 0 {
                items.append(.fill(rect, color(s.BackgroundColor), draw.Radii.zero))
            }
            var widths = b.Border
            if !sp.IsFirst { widths.Left = 0 }
            if !sp.IsLast { widths.Right = 0 }
            if widths.Top > 0 || widths.Bottom > 0 || widths.Left > 0 || widths.Right > 0 {
                var colors: [draw.Color] = []
                var side = 0
                while side < 4 {
                    colors.append(color(borderSideColor(s, side)))
                    side += 1
                }
                items.append(.border(rect, widths, colors, draw.Radii.zero))
            }
        }
        for f in line.Fragments {
            switch f.Kind {
            case .text, .marker:
                if f.Owner.Style.Visibility != .visible { continue }
                let textColor = color(f.Owner.Style.Color)
                if f.Run.Count > 0 {
                    items.append(.text(x + f.X, y + f.Y + f.Ascent, f.Run, textColor, f.Owner.Style.LetterSpacing))
                }
                if !f.Decoration.IsNone {
                    let face = f.Owner.Style.Face
                    let thickness = face.Size / 14 > 1 ? face.Size / 14 : 1
                    let c = color(f.DecorationColor)
                    let baseline = y + f.Y + f.Ascent
                    if f.Decoration.Underline {
                        items.append(.fill(draw.Rect(x + f.X, baseline + face.Descent * 0.4, f.Width, thickness), c, draw.Radii.zero))
                    }
                    if f.Decoration.LineThrough {
                        items.append(.fill(draw.Rect(x + f.X, baseline - face.XHeight / 2, f.Width, thickness), c, draw.Radii.zero))
                    }
                    if f.Decoration.Overline {
                        items.append(.fill(draw.Rect(x + f.X, baseline - face.Ascent, f.Width, thickness), c, draw.Radii.zero))
                    }
                }
            case .atomic:
                paintBox(f.Box, x: x, y: y, skipBackground: 0)
            }
        }
    }

    /// Paints what a control or image shows inside its box.
    func paintReplaced(_ box: Box, x: float32, y: float32) {
        let s = box.Style
        let inner = draw.Rect(x + box.ContentX, y + box.ContentY, box.InnerWidth, box.InnerHeight)
        let face = s.Face
        let isFocused = box.Node != nil && box.Node!.Id == focused
        switch box.Replaced {
        case .image:
            if let img = box.Image {
                items.append(.image(inner, img, opacity))
            } else {
                // No image: a faint frame, as browsers show a broken image.
                let c = color(draw.Color(200, 200, 200))
                items.append(.border(inner, draw.Edges(all: 1), [c, c, c, c], draw.Radii.zero))
                if let alt = box.Node?.GetAttribute("alt"), !alt.isEmpty {
                    let run = face.Shape(alt)
                    items.append(.clip(inner))
                    items.append(.text(inner.X + 2, inner.Y + face.Ascent + 2, run, color(s.Color), 0))
                    items.append(PaintItem.unclip)
                }
            }
        case .textInput, .textArea:
            items.append(.clip(inner))
            let textX = inner.X + 1
            var textY = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            if box.Replaced == .textArea { textY = inner.Y + face.Ascent + (face.LineHeight - face.Ascent - face.Descent) / 2 }
            let value = box.Text
            var caretX = textX
            if !value.isEmpty {
                if box.Replaced == .textArea {
                    var lineY = textY
                    var lineStart = 0
                    let bytes = [uint8](value.utf8)
                    var i = 0
                    var caretPlaced = false
                    while i <= bytes.count {
                        if i == bytes.count || bytes[i] == 10 {
                            let lineText = draw.stringOf(bytes, lineStart, i)
                            let run = face.Shape(lineText)
                            if run.Count > 0 { items.append(.text(textX, lineY, run, color(s.Color), 0)) }
                            if isFocused && caret >= lineStart && caret <= i && !caretPlaced {
                                caretX = textX + face.Measure(draw.stringOf(bytes, lineStart, caret))
                                caretPlaced = true
                                if caretVisible {
                                    items.append(.fill(draw.Rect(caretX, lineY - face.Ascent, 1, face.Ascent + face.Descent), color(s.Color), draw.Radii.zero))
                                }
                            }
                            lineY += face.LineHeight
                            lineStart = i + 1
                        }
                        i += 1
                    }
                } else {
                    let run = face.Shape(value)
                    items.append(.text(textX, textY, run, color(s.Color), 0))
                    if isFocused {
                        let bytes = [uint8](value.utf8)
                        let upto = caret < 0 ? 0 : (caret > bytes.count ? bytes.count : caret)
                        caretX = textX + face.Measure(draw.stringOf(bytes, 0, upto))
                    }
                }
            } else if let placeholder = box.Node?.GetAttribute("placeholder"), !placeholder.isEmpty {
                let run = face.Shape(placeholder)
                items.append(.text(textX, textY, run, color(draw.Color(117, 117, 117)), 0))
            }
            if isFocused && caretVisible && (value.isEmpty || box.Replaced == .textInput) {
                items.append(.fill(draw.Rect(caretX, textY - face.Ascent, 1, face.Ascent + face.Descent), color(s.Color), draw.Radii.zero))
            }
            items.append(PaintItem.unclip)
        case .button:
            let run = face.Shape(box.Text)
            let tx = inner.X + (inner.Width - run.Width) / 2
            let ty = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.clip(inner))
            items.append(.text(tx, ty, run, color(s.Color), 0))
            items.append(PaintItem.unclip)
        case .checkbox, .radio:
            let checked = box.Node?.HasAttribute("checked") ?? false
            let radius = box.Replaced == .radio ? box.Width / 2 : s.BorderRadius.TopLeft
            let rect = draw.Rect(x, y, box.Width, box.Height)
            if checked {
                let accent = color(draw.Color(0, 117, 255))
                items.append(.fill(rect, accent, draw.Radii(all: radius)))
                if box.Replaced == .radio {
                    let dot = draw.Rect(x + box.Width * 0.3, y + box.Height * 0.3, box.Width * 0.4, box.Height * 0.4)
                    items.append(.fill(dot, color(draw.Color.white), draw.Radii(all: box.Width * 0.2)))
                } else {
                    let mark = font.Load(font.Spec(family: "system-ui", size: box.Height * 0.85, weight: 700)).Shape("✓")
                    items.append(.text(x + (box.Width - mark.Width) / 2, y + box.Height * 0.8, mark, color(draw.Color.white), 0))
                }
            }
        case .select:
            let run = face.Shape(box.Text)
            let ty = inner.Y + (inner.Height - face.LineHeight) / 2 + face.Ascent
            items.append(.clip(inner))
            items.append(.text(inner.X, ty, run, color(s.Color), 0))
            items.append(PaintItem.unclip)
            let arrow = face.Shape("▾")
            items.append(.text(x + box.Width - box.Border.Right - 16, ty, arrow, color(s.Color), 0))
        case .progress:
            let track = draw.Rect(x, y, box.Width, box.Height)
            items.append(.fill(track, color(draw.Color(230, 230, 230)), draw.Radii(all: box.Height / 2)))
            var fraction: float32 = 0
            if let v = box.Node?.GetAttribute("value") {
                let vb = [uint8](v.utf8)
                var max: float32 = 1
                if let m = box.Node?.GetAttribute("max") {
                    let mb = [uint8](m.utf8)
                    max = draw.parseNumber(mb, 0, mb.count)
                }
                if max > 0 { fraction = clampf(draw.parseNumber(vb, 0, vb.count) / max, 0, 1) }
            }
            if fraction > 0 {
                items.append(.fill(draw.Rect(x, y, box.Width * fraction, box.Height), color(draw.Color(0, 117, 255)), draw.Radii(all: box.Height / 2)))
            }
        case .placeholder:
            let rect = draw.Rect(x, y, box.Width, box.Height)
            items.append(.fill(rect, color(draw.Color(235, 235, 235)), draw.Radii.zero))
        case .none:
            break
        }
    }

    func sortByZIndex(_ list: inout [Box]) {
        var i = 1
        while i < list.count {
            let b = list[i]
            var j = i - 1
            while j >= 0 && list[j].Style.ZIndex > b.Style.ZIndex {
                list[j + 1] = list[j]
                j -= 1
            }
            list[j + 1] = b
            i += 1
        }
    }
}

/// Paints a display list onto a canvas: page coordinates are scaled by
/// the device scale and shifted by the view's origin and scroll.
func rasterize(_ items: [PaintItem], on base: draw.Canvas, scale: float32, originX: float32, originY: float32,
               scrollX: float32, scrollY: float32) {
    var canvas = base
    var clips: [draw.IRect] = []
    let dx = originX - scrollX * scale
    let dy = originY - scrollY * scale
    func device(_ r: draw.Rect) -> draw.IRect {
        let x0 = draw.roundToInt(r.X * scale + dx)
        let y0 = draw.roundToInt(r.Y * scale + dy)
        let x1 = draw.roundToInt((r.X + r.Width) * scale + dx)
        let y1 = draw.roundToInt((r.Y + r.Height) * scale + dy)
        return draw.IRect(x0, y0, x1 - x0, y1 - y0)
    }
    for item in items {
        switch item.Kind {
        case .fill:
            let r = item.Rect
            let c = item.Color
            let radii = item.Radii
            let dr = device(r)
            if dr.IsEmpty {
                // A hairline that rounded away: keep it a pixel.
                if r.Width > 0 && r.Height > 0 && (dr.Width <= 0 || dr.Height <= 0) {
                    canvas.Fill(draw.IRect(dr.X, dr.Y, dr.Width > 0 ? dr.Width : 1, dr.Height > 0 ? dr.Height : 1), c)
                }
                continue
            }
            if radii.IsZero {
                canvas.Fill(dr, c)
            } else {
                canvas.FillRounded(dr, radii: radii.Scaled(scale), c)
            }
        case .border:
            let r = item.Rect
            let widths = item.Widths
            let colors = item.Colors
            let radii = item.Radii
            let dr = device(r)
            if dr.IsEmpty { continue }
            var w = draw.Edges(roundf(widths.Top * scale), roundf(widths.Right * scale), roundf(widths.Bottom * scale), roundf(widths.Left * scale))
            if widths.Top > 0 && w.Top < 1 { w.Top = 1 }
            if widths.Right > 0 && w.Right < 1 { w.Right = 1 }
            if widths.Bottom > 0 && w.Bottom < 1 { w.Bottom = 1 }
            if widths.Left > 0 && w.Left < 1 { w.Left = 1 }
            canvas.FillRing(dr, radii: radii.Scaled(scale), widths: w, colors: colors)
        case .text:
            let x = item.X
            let baseline = item.Y
            let run = item.Run
            let c = item.Color
            let letterSpacing = item.LetterSpacing
            if letterSpacing == 0 {
                font.DrawRun(canvas, run, x: x * scale + dx, baseline: baseline * scale + dy, scale: scale, color: c)
            } else {
                var pen = x * scale + dx
                var i = 0
                while i < run.Glyphs.count {
                    let g = font.GlyphMask(face: run.Faces[i], glyph: run.Glyphs[i], scale: scale)
                    if !g.IsEmpty {
                        canvas.DrawMask(g.Mask, x: draw.roundToInt(pen) + g.Left, y: draw.roundToInt(baseline * scale + dy) - g.Top, c)
                    }
                    pen += (run.Advances[i] + letterSpacing) * scale
                    i += 1
                }
            }
        case .image:
            let dr = device(item.Rect)
            if dr.IsEmpty { continue }
            if let img = item.Image { canvas.DrawImage(img, into: dr, opacity: item.Opacity) }
        case .clip:
            clips.append(canvas.Clip)
            canvas.ClipTo(device(item.Rect))
        case .unclip:
            if let saved = clips.popLast() {
                canvas.Clip = saved
            }
        }
    }
}
