package font

import cfont
import "ui/draw"

/// What a font is asked for, in CSS terms: a list of families to try in
/// order, a size in CSS pixels, a weight from 100 to 900 and a slant.
public struct Spec: Equatable {
    public var Families: [string]
    public var Size: float32
    public var Weight: int32
    public var Italic: bool

    public init(families: [string], size: float32, weight: int32 = 400, italic: bool = false) {
        Families = families
        Size = size
        Weight = weight
        Italic = italic
    }

    public init(family: string, size: float32, weight: int32 = 400, italic: bool = false) {
        Families = [family]
        Size = size
        Weight = weight
        Italic = italic
    }

}

/// Text shaped into glyphs: what to draw, on which face, and how far
/// each advances the pen, in CSS pixels.
public struct Run {
    public var Glyphs: [uint32]
    public var Faces: [int32]
    public var Advances: [float32]
    public var Width: float32

    public init() {
        Glyphs = []
        Faces = []
        Advances = []
        Width = 0
    }

    public var Count: int { return Glyphs.count }
}

/// A font at one size. Faces are shared: `Load` answers the same one for
/// the same spec, and each keeps what it has shaped.
public final class Face {
    /// The platform's number for it.
    public let Id: int32
    public let Spec: Spec
    /// The family that answered, of those the spec listed.
    public let Family: string
    public let Size: float32
    /// Distances from the baseline, in CSS pixels, both positive.
    public let Ascent: float32
    public let Descent: float32
    /// The gap the designer leaves between lines, which `line-height:
    /// normal` adds to the ascent and descent.
    public let Leading: float32
    public let XHeight: float32
    public let SpaceWidth: float32

    var runs: [string: Run] = [:]

    init(id: int32, spec: Spec, family: string) {
        Id = id
        self.Spec = spec
        Family = family
        Size = spec.Size
        var ascent: double = 0
        var descent: double = 0
        var leading: double = 0
        var xHeight: double = 0
        var space: double = 0
        cfont_metrics(id, &ascent, &descent, &leading, &xHeight, &space)
        Ascent = float32(ascent)
        Descent = float32(descent)
        Leading = float32(leading)
        XHeight = float32(xHeight)
        SpaceWidth = float32(space)
    }

    /// The height of a line of this face when line-height is `normal`.
    public var LineHeight: float32 { return Ascent + Descent + Leading }

    /// Shapes a word: glyphs and advances, kept for the next time the
    /// same word is asked for. A browser shapes per word for the same
    /// reason: pages repeat theirs.
    public func Shape(_ text: string) -> Run {
        if let cached = runs[text] {
            return cached
        }
        let run = shape(text)
        runs[text] = run
        return run
    }

    func shape(_ text: string) -> Run {
        var run = Run()
        let bytes = [uint8](text.utf8)
        if bytes.isEmpty { return run }
        var cap = bytes.count + 4
        while true {
            var glyphs = [uint32](repeating: 0, count: cap)
            var faces = [int32](repeating: 0, count: cap)
            var advances = [float32](repeating: 0, count: cap)
            let n = bytes.withUnsafeBytes { bp in
                glyphs.withUnsafeMutableBufferPointer { gp in
                    faces.withUnsafeMutableBufferPointer { fp in
                        advances.withUnsafeMutableBufferPointer { ap in
                            cfont_shape(Id, UnsafePointer<CChar>(bp.baseAddress!), int32(bytes.count),
                                        gp.baseAddress!, fp.baseAddress!, ap.baseAddress!, int32(cap))
                        }
                    }
                }
            }
            if int(n) <= cap {
                var i = 0
                var width: float32 = 0
                while i < int(n) {
                    run.Glyphs.append(glyphs[i])
                    run.Faces.append(faces[i])
                    run.Advances.append(advances[i])
                    width += advances[i]
                    i += 1
                }
                run.Width = width
                return run
            }
            cap = int(n)
        }
    }

    /// The width of text set in this face.
    public func Measure(_ text: string) -> float32 {
        return Shape(text).Width
    }
}

// Faces by their first family, then by the rest of the spec: a page uses
// a family at a few sizes and weights, so the list is short.
var faces: [string: [Face]] = [:]

// Family names a page gave font files, mapped to what the files call
// themselves.
var aliases: [string: string] = [:]

/// Registers a font file so that its family can be used, under the name
/// given, as @font-face does. Answers false where the file is not a font.
public func Register(path: string, as name: string) -> bool {
    var buf = [CChar](repeating: 0, count: 256)
    let ok = buf.withUnsafeMutableBufferPointer { bp in
        cfont_register(path, bp.baseAddress, int32(bp.count))
    }
    if ok == 0 { return false }
    let family = string(cString: buf)
    if !family.isEmpty {
        aliases[trimQuotes(name)] = family
        faces = [:]
    }
    return true
}

/// The face for a spec: the first of its families the system has, at
/// the size, weight and slant asked for, or the platform's sans-serif
/// where it has none of them.
public func Load(_ spec: Spec) -> Face {
    let key = spec.Families.isEmpty ? "" : spec.Families[0]
    let known = faces[key] ?? []
    for f in known {
        if f.Spec.Size == spec.Size && f.Spec.Weight == spec.Weight && f.Spec.Italic == spec.Italic && sameList(f.Spec.Families, spec.Families) {
            return f
        }
    }
    var size = spec.Size
    if size <= 0 { size = 16 }
    var id: int32 = -1
    var family = ""
    var i = 0
    while i < spec.Families.count && id < 0 {
        var name = trimQuotes(spec.Families[i])
        if let real = aliases[name] { name = real }
        if !name.isEmpty {
            id = cfont_face(name, double(size), spec.Weight, spec.Italic ? 1 : 0)
            family = name
        }
        i += 1
    }
    if id < 0 {
        family = "sans-serif"
        id = cfont_face(family, double(size), spec.Weight, spec.Italic ? 1 : 0)
    }
    var used = spec
    used.Size = size
    let face = Face(id: id, spec: used, family: family)
    var list = known
    list.append(face)
    faces[key] = list
    return face
}

func sameList(_ a: [string], _ b: [string]) -> bool {
    if a.count != b.count { return false }
    var i = 0
    while i < a.count {
        if a[i] != b[i] { return false }
        i += 1
    }
    return true
}

func trimQuotes(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 34 || b[start] == 39 || b[start] == 9) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 34 || b[end - 1] == 39 || b[end - 1] == 9) { end -= 1 }
    if start == 0 && end == b.count { return s }
    return draw.stringOf(b, start, end)
}

/// A glyph's coverage, rasterized at some scale: the mask, and where its
/// top-left corner sits relative to the glyph's origin on the baseline,
/// in device pixels.
public struct Glyph {
    public var Mask: draw.Mask
    public var Left: int32
    public var Top: int32

    public var IsEmpty: bool { return Mask.Width <= 0 || Mask.Height <= 0 }
}

var glyphs: [uint64: Glyph] = [:]

/// The mask for a glyph of a face at a scale, rasterized once and kept.
/// Scales are kept to sixteenths, which is finer than any display's.
public func GlyphMask(face: int32, glyph: uint32, scale: float32) -> Glyph {
    let q = uint64(scale * 16 + 0.5)
    let key = (uint64(face) << 40) | (uint64(glyph) << 8) | (q & 0xFF)
    if let cached = glyphs[key] {
        return cached
    }
    let made = rasterize(face: face, glyph: glyph, scale: float32(q) / 16)
    glyphs[key] = made
    return made
}

func rasterize(face: int32, glyph: uint32, scale: float32) -> Glyph {
    var left: int32 = 0
    var top: int32 = 0
    var width: int32 = 0
    var height: int32 = 0
    var need = cfont_glyph(face, glyph, double(scale), &left, &top, &width, &height, nil, 0)
    if need <= 0 || width <= 0 || height <= 0 {
        return Glyph(Mask: draw.Mask(width: 0, height: 0, data: []), Left: 0, Top: 0)
    }
    var data = [uint8](repeating: 0, count: int(need))
    need = data.withUnsafeMutableBufferPointer { dp in
        cfont_glyph(face, glyph, double(scale), &left, &top, &width, &height, dp.baseAddress!, int32(dp.count))
    }
    return Glyph(Mask: draw.Mask(width: width, height: height, data: data), Left: left, Top: top)
}

/// Draws a run on a canvas with its origin at (x, baseline) in device
/// pixels, at a scale: the glyphs are rasterized at that scale and each
/// pen advance is scaled to match.
public func DrawRun(_ canvas: draw.Canvas, _ run: Run, x: float32, baseline: float32, scale: float32, color: draw.Color) {
    if color.A == 0 { return }
    var pen = x
    var i = 0
    while i < run.Glyphs.count {
        let g = GlyphMask(face: run.Faces[i], glyph: run.Glyphs[i], scale: scale)
        if !g.IsEmpty {
            canvas.DrawMask(g.Mask, x: draw.roundToInt(pen) + g.Left, y: draw.roundToInt(baseline) - g.Top, color)
        }
        pen += run.Advances[i] * scale
        i += 1
    }
}
