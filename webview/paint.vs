package webview

import "text/html"
import "ui/draw"
import "ui/font"

public enum PaintKind: Equatable {
    case fill
    case border
    case text
    case image
    case gradient
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
    /// An image's tile size and whether it repeats each way; the rect is
    /// the area it covers.
    public var TileWidth: float32
    public var TileHeight: float32
    public var RepeatX: bool
    public var RepeatY: bool
    public var Gradient: draw.LinearGradient?

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
        TileWidth = 0
        TileHeight = 0
        RepeatX = false
        RepeatY = false
        Gradient = nil
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

    static func gradient(_ r: draw.Rect, _ g: draw.LinearGradient, _ radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.gradient)
        it.Rect = r
        it.Gradient = g
        it.Radii = radii
        return it
    }

    static func tiles(_ area: draw.Rect, _ img: draw.Image, tileWidth: float32, tileHeight: float32,
                      originX: float32, originY: float32, repeatX: Bool, repeatY: Bool, opacity: float32, radii: draw.Radii) -> PaintItem {
        var it = PaintItem(.image)
        it.Rect = area
        it.Radii = radii
        it.Image = img
        it.TileWidth = tileWidth
        it.TileHeight = tileHeight
        it.X = originX
        it.Y = originY
        it.RepeatX = repeatX
        it.RepeatY = repeatY
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
    /// The page's images by URL, for backgrounds.
    var images: [string: draw.Image] = [:]
    /// The selection, if any, and each text node's place in the document.
    var selectionStart: TextPosition? = nil
    var selectionEnd: TextPosition? = nil
    var textOrder: [int64: int] = [:]

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
            // A scroll container whose content overflows shows a thin bar
            // where it is scrolled to.
            if s.IsScrollContainer && box.ContentHeight > box.InnerHeight + 0.5 && box.InnerHeight > 20 {
                let trackTop = y + box.Border.Top + 2
                let trackHeight = box.PaddingBoxHeight - 4
                let thumb = trackHeight * box.InnerHeight / box.ContentHeight
                let maxScroll = box.ContentHeight - box.InnerHeight
                let thumbY = trackTop + (trackHeight - thumb) * (maxScroll > 0 ? box.ScrollY / maxScroll : 0)
                let bar = draw.Rect(x + box.Width - box.Border.Right - 8, thumbY, 5, thumb)
                items.append(.fill(bar, color(draw.Color(0, 0, 0, 80)), draw.Radii(all: 2.5)))
            }
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
        // Shadows go under the box: each drawn as rings from the blur's
        // outer edge inward, which fades like a blur near enough.
        for sh in s.Shadows where !sh.Inset && sh.Color.A > 0 {
            let steps = sh.Blur > 1 ? (sh.Blur > 12 ? 12 : int(sh.Blur)) : 1
            let each = color(sh.Color).Faded(1 / float32(steps))
            var i = 0
            while i < steps {
                let grow = sh.Spread + sh.Blur / 2 - sh.Blur * float32(i) / float32(steps)
                let r = draw.Rect(x + sh.X - grow, y + sh.Y - grow, box.Width + 2 * grow, box.Height + 2 * grow)
                if r.Width > 0 && r.Height > 0 {
                    items.append(.fill(r, each, draw.Radii(all: (radii.IsZero ? 0 : radii.TopLeft) + grow)))
                }
                i += 1
            }
        }
        if s.BackgroundColor.A > 0 {
            items.append(.fill(rect, color(s.BackgroundColor), radii))
        }
        if let bg = s.BackgroundImage {
            let paddingBox = draw.Rect(x + box.Border.Left, y + box.Border.Top, box.PaddingBoxWidth, box.PaddingBoxHeight)
            if let g = bg.Gradient {
                items.append(.gradient(paddingBox, g, radii.Inset(box.Border)))
            } else if !bg.URL.isEmpty, let img = images[bg.URL], img.Width > 0 && img.Height > 0 {
                var tw = float32(img.Width)
                var th = float32(img.Height)
                switch bg.Size {
                case .cover:
                    let scale = maxf(paddingBox.Width / tw, paddingBox.Height / th)
                    tw *= scale
                    th *= scale
                case .contain:
                    let scale = minf(paddingBox.Width / tw, paddingBox.Height / th)
                    tw *= scale
                    th *= scale
                case .length(let w, let h):
                    let rw = w.Resolve(paddingBox.Width)
                    let rh = h.Resolve(paddingBox.Height)
                    if let a = rw, let b = rh { tw = a; th = b }
                    else if let a = rw { th = th * a / tw; tw = a }
                    else if let b = rh { tw = tw * b / th; th = b }
                case .auto:
                    break
                }
                let ox = paddingBox.X + (paddingBox.Width - tw) * bg.PositionX
                let oy = paddingBox.Y + (paddingBox.Height - th) * bg.PositionY
                items.append(.tiles(paddingBox, img, tileWidth: tw, tileHeight: th, originX: ox, originY: oy,
                                    repeatX: bg.RepeatX, repeatY: bg.RepeatY, opacity: opacity, radii: radii.Inset(box.Border)))
            }
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
        // The selection's highlight goes under the text.
        if let start = selectionStart, let end = selectionEnd {
            for f in line.Fragments where f.Kind == .text {
                guard let node = f.Box.Node else { continue }
                if let part = selectedPart(f, node, (start: start, end: end), textOrder) {
                    let face = f.Owner.Style.Face
                    let bytes = [uint8](f.Text.utf8)
                    let x0 = x + f.X + face.Measure(draw.stringOf(bytes, 0, part.from))
                    let x1 = part.to >= bytes.count ? x + f.X + f.Width : x + f.X + face.Measure(draw.stringOf(bytes, 0, part.to))
                    items.append(.fill(draw.Rect(x0, y + line.Y, x1 - x0, line.Height), draw.Color(179, 212, 252), draw.Radii.zero))
                }
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
            guard let img = item.Image else { continue }
            if item.TileWidth <= 0 {
                let dr = device(item.Rect)
                if dr.IsEmpty { continue }
                canvas.DrawImage(img, into: dr, opacity: item.Opacity)
                continue
            }
            // A background: tiles from the origin across the area, only
            // the ones that show, kept inside the box's curves.
            let area = device(item.Rect)
            if area.IsEmpty { continue }
            var tiled = canvas
            tiled.ClipTo(area)
            if tiled.Clip.IsEmpty { continue }
            let shapeRadii = item.Radii.Scaled(scale)
            let tw = item.TileWidth * scale
            let th = item.TileHeight * scale
            if tw < 1 || th < 1 { continue }
            let ox = item.X * scale + dx
            let oy = item.Y * scale + dy
            var startX = ox
            var startY = oy
            if item.RepeatX { startX = ox - c_ceilf((ox - float32(tiled.Clip.X)) / tw) * tw }
            if item.RepeatY { startY = oy - c_ceilf((oy - float32(tiled.Clip.Y)) / th) * th }
            var ty = startY
            var rows = 0
            while ty < float32(tiled.Clip.Bottom) && rows < 4096 {
                var tx = startX
                var cols = 0
                while tx < float32(tiled.Clip.Right) && cols < 4096 {
                    let x0 = draw.roundToInt(tx)
                    let y0 = draw.roundToInt(ty)
                    let x1 = draw.roundToInt(tx + tw)
                    let y1 = draw.roundToInt(ty + th)
                    tiled.DrawImage(img, into: draw.IRect(x0, y0, x1 - x0, y1 - y0), opacity: item.Opacity, shape: area, radii: shapeRadii)
                    if !item.RepeatX { break }
                    tx += tw
                    cols += 1
                }
                if !item.RepeatY { break }
                ty += th
                rows += 1
            }
        case .gradient:
            let dr = device(item.Rect)
            if dr.IsEmpty { continue }
            if let g = item.Gradient { canvas.FillGradient(dr, radii: item.Radii.Scaled(scale), g) }
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

/// The part of a text fragment inside a selection, as byte offsets
/// into the fragment's text, or nil for none.
func selectedPart(_ f: Fragment, _ node: html.Node, _ range: (start: TextPosition, end: TextPosition),
                  _ order: [int64: int]) -> (from: int, to: int)? {
    let o = order[node.Id] ?? 0
    let so = order[range.start.Node.Id] ?? 0
    let eo = order[range.end.Node.Id] ?? 0
    if o < so || o > eo { return nil }
    let length = f.Text.utf8.count
    // Fragment offsets count the box's original text; a fragment's
    // text may be shorter where spaces collapsed, so the end is
    // clamped to its length.
    var from = 0
    var to = length
    if o == so {
        from = range.start.Offset - f.Offset
        if from < 0 { from = 0 }
    }
    if o == eo {
        to = range.end.Offset - f.Offset
        if to > length { to = length }
    }
    if from >= to { return nil }
    return (from: from, to: to)
}
