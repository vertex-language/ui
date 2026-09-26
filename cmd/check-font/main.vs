// Fonts checked: metrics, shaping, glyph masks, drawing.
package main

import "ui/draw"
import "ui/font"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func main() -> int32 {
    let face = font.Load(font.Spec(family: "system-ui", size: 16))
    check(face.Id > 0, "system-ui face loads (id \(face.Id))")
    check(face.Ascent > 10 && face.Ascent < 20, "ascent is plausible for 16px (got \(face.Ascent))")
    check(face.Descent > 2 && face.Descent < 8, "descent is plausible (got \(face.Descent))")
    check(face.SpaceWidth > 2 && face.SpaceWidth < 8, "space width is plausible (got \(face.SpaceWidth))")
    check(face.LineHeight >= face.Ascent + face.Descent, "line height covers ascent and descent")

    let same = font.Load(font.Spec(family: "system-ui", size: 16))
    check(same.Id == face.Id, "the same spec answers the same face")

    let run = face.Shape("Hello")
    check(run.Count == 5, "Hello shapes to five glyphs (got \(run.Count))")
    check(run.Width > 30 && run.Width < 50, "Hello is 30 to 50px wide at 16px (got \(run.Width))")
    let again = face.Shape("Hello")
    check(again.Width == run.Width, "shaping is cached and stable")
    check(face.Measure("") == 0, "empty text measures zero")
    let wide = face.Shape("Hello, world")
    check(wide.Width > run.Width, "longer text is wider")

    let bold = font.Load(font.Spec(family: "system-ui", size: 16, weight: 700))
    check(bold.Id != face.Id, "bold is another face")
    check(bold.Shape("Hello").Width > run.Width, "bold Hello is wider than regular")

    let big = font.Load(font.Spec(family: "system-ui", size: 32))
    let bigRun = big.Shape("Hello")
    check(bigRun.Width > run.Width * 1.9 && bigRun.Width < run.Width * 2.1, "32px is twice as wide as 16px (got \(bigRun.Width) vs \(run.Width))")

    let mono = font.Load(font.Spec(family: "monospace", size: 16))
    let mi = mono.Shape("i").Width
    let mw = mono.Shape("w").Width
    check(mi == mw, "monospace i and w share a width")

    let missing = font.Load(font.Spec(families: ["No Such Family Anywhere", "serif"], size: 16))
    check(missing.Family == "serif", "an unknown family falls through to the next (got \(missing.Family))")
    let serifRun = missing.Shape("Hello")
    check(serifRun.Count == 5 && serifRun.Width > 0, "serif shapes")

    let emoji = face.Shape("a😀b")
    check(emoji.Count == 3, "emoji shapes to a glyph of its own (got \(emoji.Count))")
    var fellBack = false
    var i = 0
    while i < emoji.Count {
        if emoji.Faces[i] != face.Id { fellBack = true }
        i += 1
    }
    check(fellBack, "the emoji glyph is on a fallback face")

    let g = font.GlyphMask(face: face.Id, glyph: run.Glyphs[0], scale: 1)
    check(!g.IsEmpty, "H has a mask (\(g.Mask.Width)x\(g.Mask.Height))")
    check(g.Top > 8 && g.Top < 16, "H rises above the baseline (top \(g.Top))")
    var covered = 0
    i = 0
    while i < g.Mask.Data.count {
        if g.Mask.Data[i] > 0 { covered += 1 }
        i += 1
    }
    check(covered > 20, "H covers pixels (\(covered))")
    let g2 = font.GlyphMask(face: face.Id, glyph: run.Glyphs[0], scale: 2)
    check(g2.Mask.Width > g.Mask.Width * 3 / 2, "the 2x mask is wider (\(g2.Mask.Width) vs \(g.Mask.Width))")

    let w: int32 = 64
    let h: int32 = 32
    var pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        font.DrawRun(c, run, x: 2, baseline: 20, scale: 1, color: draw.Color.black)
    }
    var dark = 0
    var y: int32 = 0
    while y < h {
        var x: int32 = 0
        while x < w {
            if pixels[int((y * w + x) * 4)] < 128 { dark += 1 }
            x += 1
        }
        y += 1
    }
    check(dark > 40, "drawing a run darkens pixels (\(dark))")
    var belowBaseline = 0
    y = 22
    while y < h {
        var x: int32 = 0
        while x < w {
            if pixels[int((y * w + x) * 4)] < 128 { belowBaseline += 1 }
            x += 1
        }
        y += 1
    }
    check(belowBaseline == 0, "Hello has nothing below the baseline (\(belowBaseline))")

    if failures == 0 {
        print("ALL FONT CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
