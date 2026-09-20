// The webview checked headless: styles, layout, painting, input.
package main

import "text/html"
import "text/css"
import "text/css/selector"
import "ui/draw"
import "ui/webview"

typealias Display = webview.Display
typealias Length = webview.Length

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func styleOf(_ source: string, _ sel: string) -> webview.ComputedStyle? {
    let doc = html.Parse(source)
    let resolver = webview.StyleResolver(ua: webview.UserAgentRules())
    for style in doc.ElementsByTagName("style") {
        resolver.Author.Add(css.Parse(style.InnerText()))
    }
    guard let node = selector.QuerySelector(sel, in: doc.Root) else { return nil }
    // Resolve the chain from the root down, as the engine does.
    var chain: [html.Node] = []
    var cur: html.Node? = node
    while let n = cur {
        if n.Kind == html.NodeKind.element { chain.insert(n, at: 0) }
        cur = n.Parent
    }
    var parent: webview.ComputedStyle? = nil
    for n in chain {
        parent = resolver.Resolve(n, parent: parent, context: selector.MatchContext.none)
    }
    return parent
}

func testStyles() {
    print("Styles")
    let page = """
    <style>
      body { font-size: 20px; color: rgb(10, 20, 30); }
      .box { width: 50%; padding: 1em 2em; margin: 4px auto; border: 2px solid #ff0000; border-radius: 6px 3px; }
      #big { font-size: 2em; line-height: 1.5; }
      p { color: blue !important; }
      p.red { color: red; }
      .hidden { display: none }
      span { font-weight: bold; text-decoration: underline; }
      .flex { display: flex; flex-direction: column; gap: 10px 20px; justify-content: space-between; }
      .item { flex: 2 1 100px; }
      @media (max-width: 500px) { .box { width: 100px; } }
      @media screen and (min-width: 500px) { .box { max-width: 300px; } }
      .rem { margin-left: 2rem; font: italic 700 12px/2 Georgia, serif; }
    </style>
    <div class="box" id="big">
      <p class="red">text <span style="color: green; font-weight: normal">inner</span></p>
      <div class="flex"><div class="item"></div></div>
      <p class="rem">r</p>
    </div>
    """
    guard let body = styleOf(page, "body") else { check(false, "body resolves"); return }
    check(body.Display == .block, "body is a block")
    check(body.FontSize == 20, "body font-size 20px (got \(body.FontSize))")
    check(body.MarginTop == .px(8), "body has the UA's 8px margin")
    check(body.Color == draw.Color(10, 20, 30), "rgb() color")

    guard let box = styleOf(page, ".box") else { check(false, "box resolves"); return }
    check(box.FontSize == 40, "2em of 20px is 40px (got \(box.FontSize))")
    check(box.Width == .percent(50), "width: 50% stays a percentage")
    check(box.PaddingTop == .px(40) && box.PaddingLeft == .px(80), "padding in em uses the element's own font size (got \(box.PaddingTop) \(box.PaddingLeft))")
    check(box.MarginTop == .px(4) && box.MarginLeft == .auto, "margin: 4px auto")
    check(box.BorderTopWidth == 2 && box.BorderLeftStyle == .solid && box.BorderTopColor == draw.Color(255, 0, 0), "border shorthand sets width, style and color")
    check(box.BorderRadius.TopLeft == 6 && box.BorderRadius.TopRight == 3 && box.BorderRadius.BottomRight == 6, "border-radius with two values")
    check(box.LineHeight == .number(1.5) && box.LineHeightPx == 60, "unitless line-height multiplies the font size (got \(box.LineHeightPx))")
    check(box.MaxWidth == .px(300), "a matching @media rule applies")
    check(box.Width != .px(100), "a non-matching @media rule does not")

    guard let p = styleOf(page, "p.red") else { check(false, "p resolves"); return }
    check(p.Color == draw.Color(0, 0, 255), "!important beats a more specific rule")
    check(p.FontSize == 40, "font-size inherits")
    check(p.Display == .block && p.MarginTop == .px(40), "p margin 1em of the inherited 40px")

    guard let span = styleOf(page, "span") else { check(false, "span resolves"); return }
    check(span.Color == draw.Color(0, 128, 0), "inline style beats the sheet (got \(span.Color.R) \(span.Color.G) \(span.Color.B))")
    check(span.FontWeight == 400, "inline style sets weight normal")
    check(span.TextDecoration.Underline, "text-decoration: underline")
    check(span.Display == .inline, "span is inline")

    guard let hidden = styleOf("<style>.hidden{display:none}</style><p class=hidden>x</p>", ".hidden") else { check(false, "hidden resolves"); return }
    check(hidden.Display == .none, "display: none")

    guard let flex = styleOf(page, ".flex") else { check(false, "flex resolves"); return }
    check(flex.Display == .flex && flex.FlexDirection == .column, "display: flex, column")
    check(flex.RowGap == .px(10) && flex.ColumnGap == .px(20), "gap: 10px 20px")
    check(flex.JustifyContent == .spaceBetween, "justify-content")
    guard let item = styleOf(page, ".item") else { check(false, "item resolves"); return }
    check(item.FlexGrow == 2 && item.FlexShrink == 1 && item.FlexBasis == .px(100), "flex: 2 1 100px")

    guard let rem = styleOf(page, ".rem") else { check(false, "rem resolves"); return }
    check(rem.MarginLeft == .px(32), "2rem against the root's 16px (got \(rem.MarginLeft))")
    check(rem.FontStyle == .italic && rem.FontWeight == 700 && rem.FontSize == 12, "font shorthand: style weight size")
    check(rem.LineHeight == .number(2), "font shorthand: line-height")
    check(rem.FontFamilies.count == 2 && rem.FontFamilies[0] == "Georgia" && rem.FontFamilies[1] == "serif", "font shorthand: families")

    let h1 = styleOf("<h1>x</h1>", "h1")
    check(h1?.FontSize == 32 && h1?.FontWeight == 700, "h1 is 2em bold by default")
    let a = styleOf("<a href=x>x</a>", "a")
    check(a?.Cursor == .pointer && a?.TextDecoration.Underline == true, "a link is underlined with a pointer cursor")
    let li = styleOf("<ul><li>x</li></ul>", "li")
    check(li?.Display == .listItem && li?.ListStyleType == .disc, "li is a list item with a disc")
    let nested = styleOf("<ul><li><ul><li>x</li></ul></li></ul>", "ul ul li")
    check(nested?.ListStyleType == .circle, "nested lists use circles")
    let input = styleOf("<input>", "input")
    check(input?.Display == .inlineBlock && input?.BorderTopWidth == 1 && input?.BoxSizing == .borderBox, "inputs are bordered inline blocks")
    let hiddenAttr = styleOf("<div hidden>x</div>", "div")
    check(hiddenAttr?.Display == Display.none, "the hidden attribute hides")
    let img = styleOf("<img width=40 height=30>", "img")
    check(img?.Width == .px(40) && img?.Height == .px(30), "img width and height attributes")
    let floated = styleOf("<span style='float: left'>x</span>", "span")
    check(floated?.Display == .block && floated?.Float == .left, "a floated inline becomes a block")
    let noStyleBorder = styleOf("<div style='border-width: 4px'>x</div>", "div")
    check(noStyleBorder?.BorderTopWidth == 0, "a border with no style has no width")
    let inheritColor = styleOf("<div style='color: red'><p style='border-color: currentcolor; color: inherit'>x</p></div>", "p")
    check(inheritColor?.Color == draw.Color(255, 0, 0) && inheritColor?.BorderTopColor == nil, "inherit and currentcolor")
    let percentFont = styleOf("<div style='font-size: 10px'><p style='font-size: 150%'>x</p></div>", "p")
    check(percentFont?.FontSize == 15, "percentage font-size is of the parent")
    let bg = styleOf("<div style='background: url(x.png) #123456 no-repeat'>x</div>", "div")
    check(bg?.BackgroundColor == draw.Color(0x12, 0x34, 0x56) && bg?.BackgroundImage?.URL == "x.png", "background shorthand with a url and a color")
    let shadow = styleOf("<div style='box-shadow: 0 2px 4px rgba(0,0,0,.5), inset 1px 1px red'>x</div>", "div")
    check(shadow?.Shadows.count == 2 && shadow?.Shadows[0].Blur == 4 && shadow?.Shadows[1].Inset == true, "box-shadow list")
    let vw = styleOf("<div style='width: 50vw'>x</div>", "div")
    check(vw?.Width == .px(400), "vw against the resolver's 800px viewport")
    let calc = styleOf("<div style='width: calc(100% - 20px); margin-left: calc(1em + 2px); font-size: 10px; height: calc(2 * 7px); padding: calc(3px + 1px) calc(50% / 2)'>x</div>", "div")!
    check(calc.Width == .calc(-20, 100), "calc() of a percentage and pixels stays a calc (got \(calc.Width))")
    check(calc.MarginLeft == .px(12), "calc() of em and px resolves (got \(calc.MarginLeft))")
    check(calc.Height == .px(14) && calc.PaddingTop == .px(4) && calc.PaddingLeft == .percent(25), "calc() multiplies and divides (got \(calc.Height) \(calc.PaddingTop) \(calc.PaddingLeft))")
    let mm = styleOf("<div style='width: min(30px, 20px); height: max(1px, 5px); margin-top: clamp(4px, 9px, 6px)'>x</div>", "div")!
    check(mm.Width == .px(20) && mm.Height == .px(5) && mm.MarginTop == .px(6), "min(), max() and clamp() fold (got \(mm.Width) \(mm.Height) \(mm.MarginTop))")
}

// MARK: - Layout

final class Laid {
    let doc: html.Document
    let root: webview.Box
    let builder: webview.BoxTreeBuilder
    init(doc: html.Document, root: webview.Box, builder: webview.BoxTreeBuilder) {
        self.doc = doc
        self.root = root
        self.builder = builder
    }
    func box(_ id: string) -> webview.Box? {
        guard let node = doc.ElementById(id) else { return nil }
        return builder.byNode[node.Id]
    }
    /// A box's border-box rect relative to the viewport.
    func rect(_ id: string) -> draw.Rect? {
        guard let b = box(id) else { return nil }
        var x = b.X
        var y = b.Y
        var p = b.Parent
        while let parent = p {
            x += parent.X
            y += parent.Y
            p = parent.Parent
        }
        return draw.Rect(x, y, b.Width, b.Height)
    }
}

func layoutOf(_ source: string, width: float32 = 800, height: float32 = 600) -> Laid? {
    let doc = html.Parse(source)
    let resolver = webview.StyleResolver(ua: webview.UserAgentRules())
    resolver.ViewportWidth = width
    resolver.ViewportHeight = height
    for style in doc.ElementsByTagName("style") {
        resolver.Author.Add(css.Parse(style.InnerText()))
    }
    let builder = webview.BoxTreeBuilder(resolver: resolver, context: selector.MatchContext.none)
    guard let root = builder.Build(doc) else { return nil }
    let layout = webview.Layout(viewportWidth: width, viewportHeight: height)
    layout.Run(root)
    return Laid(doc: doc, root: root, builder: builder)
}

func near(_ a: float32, _ b: float32, _ tolerance: float32 = 0.5) -> bool {
    let d = a - b
    return d < tolerance && d > -tolerance
}

func testBlockLayout() {
    print("Block layout")
    guard let l = layoutOf("<body style='margin:0'><div id=a style='height:50px'></div><div id=b style='height:30px;margin:20px 0'></div><div id=c style='height:10px;margin-top:10px;width:50%'></div></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    check(a == draw.Rect(0, 0, 800, 50), "the first block fills the width at the top (got \(a.X) \(a.Y) \(a.Width) \(a.Height))")
    check(b.Y == 70 && b.Height == 30, "a margin separates siblings (got y \(b.Y))")
    check(c.Y == 120, "adjacent margins collapse to the larger (got y \(c.Y))")
    check(c.Width == 400, "width: 50% of the containing block")
    let bodyBox = l.doc.ElementsByTagName("body")[0]
    let body = l.builder.byNode[bodyBox.Id]!
    check(near(body.Height, 130), "the body's height is its content's (got \(body.Height))")

    guard let m = layoutOf("<body style='margin:0'><div id=outer style='padding:10px;background:red'><p id=p style='margin:16px 0'>x</p></div><div id=next></div></body>") else { check(false, "layout"); return }
    let outer = m.rect("outer")!
    let p = m.rect("p")!
    check(p.Y == 26, "padding keeps a child's margin inside (got \(p.Y))")
    check(near(outer.Height, 20 + 32 + p.Height), "the parent's height holds the child's margins (got \(outer.Height))")

    guard let n = layoutOf("<body style='margin:0'><div id=outer><p id=p style='margin:16px 0'>x</p></div></body>") else { check(false, "layout"); return }
    let outer2 = n.rect("outer")!
    let p2 = n.rect("p")!
    check(outer2.Y == 16 && p2.Y == 16, "a first child's margin collapses through its parent (got \(outer2.Y) \(p2.Y))")

    guard let w = layoutOf("<body style='margin:0'><div id=a style='width:200px;margin:0 auto'></div><div id=b style='width:100px;padding:10px;border:5px solid;box-sizing:border-box'></div><div id=c style='width:100px;padding:10px;border:5px solid'></div><div id=d style='max-width:300px'></div><div id=e style='width:1000px;min-width:0'></div></body>") else { check(false, "layout"); return }
    check(w.rect("a")!.X == 300, "margin: auto centres (got x \(w.rect("a")!.X))")
    check(w.rect("b")!.Width == 100, "box-sizing: border-box keeps the width")
    check(w.rect("c")!.Width == 130, "content-box adds padding and border")
    check(w.rect("d")!.Width == 300, "max-width caps an auto width")
    check(w.rect("e")!.Width == 1000, "a wider box overflows rather than shrinks")
    guard let cw = layoutOf("<body style='margin:0'><div id=a style='width:calc(100% - 100px);height:10px'></div></body>") else { check(false, "layout"); return }
    check(cw.rect("a")!.Width == 700, "calc() resolves against the containing block in layout (got \(cw.rect("a")!.Width))")

    guard let h = layoutOf("<html style='height:100%'><body style='margin:0;height:100%'><div id=half style='height:50%'></div></body></html>", width: 800, height: 600) else { check(false, "layout"); return }
    check(h.rect("half")!.Height == 300, "percentage heights resolve against a definite chain (got \(h.rect("half")!.Height))")
}

func testInlineLayout() {
    print("Inline layout")
    guard let l = layoutOf("<body style='margin:0;font-size:16px;line-height:20px'><p id=p style='margin:0;width:200px'>one two three four five six seven eight nine ten eleven twelve</p></body>") else { check(false, "layout"); return }
    let p = l.box("p")!
    check(p.Lines.count > 2, "text wraps into several lines in 200px (got \(p.Lines.count))")
    check(p.Lines.count > 0 && near(p.Lines[0].Height, 20), "each line is the line-height tall (got \(p.Lines.count > 0 ? p.Lines[0].Height : -1))")
    check(near(p.Height, float32(p.Lines.count) * 20), "the paragraph is as tall as its lines")
    var allFit = true
    for line in p.Lines {
        for f in line.Fragments {
            if f.X + f.Width > 200.5 { allFit = false }
        }
    }
    check(allFit, "no line is wider than the paragraph")
    check(p.Lines.count > 1 && p.Lines[1].Fragments.count > 0 && p.Lines[1].Fragments[0].X == 0, "a later line starts at the left edge")

    guard let c = layoutOf("<body style='margin:0'><p id=p style='margin:0;width:400px;text-align:center'>hi</p><p id=r style='margin:0;width:400px;text-align:right'>hi</p></body>") else { check(false, "layout"); return }
    let cf = c.box("p")!.Lines[0].Fragments[0]
    check(near(cf.X + cf.Width / 2, 200, 1), "text-align: center centres the line (got \(cf.X + cf.Width / 2))")
    let rf = c.box("r")!.Lines[0].Fragments[0]
    check(near(rf.X + rf.Width, 400, 1), "text-align: right ends the line at the right edge")

    guard let s = layoutOf("<body style='margin:0;font-size:16px'><p id=p style='margin:0'>a <b>bold</b> <i>word</i> <span style='font-size:32px'>big</span> end</p></body>") else { check(false, "layout"); return }
    let sp = s.box("p")!
    check(sp.Lines.count == 1, "short mixed text is one line")
    let line = sp.Lines[0]
    var owners = 0
    for f in line.Fragments { if f.Owner.Node?.TagName == "b" || f.Owner.Node?.TagName == "i" { owners += 1 } }
    check(owners == 2, "inline elements own their text fragments (got \(owners))")
    check(line.Height > 30, "a bigger font makes the line taller (got \(line.Height))")
    var sameBaseline = true
    var baselineY: float32 = -1
    for f in line.Fragments {
        let b = f.Y + f.Ascent
        if baselineY < 0 { baselineY = b } else if !near(b, baselineY) { sameBaseline = false }
    }
    check(sameBaseline, "all fragments share the baseline")
    check(line.Spans.count == 3, "each inline element gets a span on the line (got \(line.Spans.count))")

    guard let w = layoutOf("<body style='margin:0'><p id=p style='margin:0;width:100px;white-space:nowrap'>one two three four five</p><pre id=pre style='margin:0'>a  b\nc</pre></body>") else { check(false, "layout"); return }
    check(w.box("p")!.Lines.count == 1, "nowrap keeps one line")
    check(w.box("pre")!.Lines.count == 2, "pre breaks at newlines (got \(w.box("pre")!.Lines.count))")
    let preLine = w.box("pre")!.Lines[0]
    check(preLine.Fragments.count == 1 && preLine.Fragments[0].Text == "a  b", "pre keeps its spaces (got \(preLine.Fragments.count) fragments)")

    guard let br = layoutOf("<body style='margin:0'><p id=p style='margin:0'>a<br>b<br><br>c</p></body>") else { check(false, "layout"); return }
    check(br.box("p")!.Lines.count == 4, "br breaks lines, an empty one too (got \(br.box("p")!.Lines.count))")

    guard let ib = layoutOf("<body style='margin:0'><p id=p style='margin:0'>x <span id=ib style='display:inline-block;width:50px;height:40px'></span> y <img id=img width=20 height=10></p></body>") else { check(false, "layout"); return }
    let ibr = ib.rect("ib")!
    check(ibr.Width == 50 && ibr.Height == 40, "an inline-block takes its width and height")
    let pl = ib.box("p")!.Lines[0]
    check(pl.Height >= 40, "the line grows to hold the inline-block (got \(pl.Height))")
    check(near(ibr.Y + 40, pl.Y + pl.Baseline), "an empty inline-block sits on the baseline (bottom \(ibr.Y + 40) baseline \(pl.Y + pl.Baseline))")
    check(ib.rect("img")!.Width == 20 && ib.rect("img")!.Height == 10, "an image takes its attributes' size")

    guard let li = layoutOf("<body style='margin:0'><ul id=ul><li id=a>one</li><li id=b>two</li></ul><ol><li id=c>x</li><li id=d>y</li></ol></body>") else { check(false, "layout"); return }
    check(li.box("a")!.Marker == "•" && li.box("c")!.Marker == "1." && li.box("d")!.Marker == "2.", "list markers count (got \(li.box("d")!.Marker))")
    check(li.rect("a")!.X == 40, "the ul's padding indents the items (got \(li.rect("a")!.X))")
    let firstLine = li.box("a")!.Lines[0]
    check(firstLine.Fragments.count == 2 && firstLine.Fragments[0].Kind == .marker && firstLine.Fragments[0].X < 0, "the marker sits outside the item's first line")

    guard let e = layoutOf("<body style='margin:0'><div id=e></div><p id=blank>   </p></body>") else { check(false, "layout"); return }
    check(e.rect("e")!.Height == 0 && e.rect("blank")!.Height == 0, "empty and blank blocks have no height")
}

func testFlexLayout() {
    print("Flex layout")
    guard let l = layoutOf("<body style='margin:0'><div id=f style='display:flex;width:600px;height:100px'><div id=a style='flex:1'></div><div id=b style='flex:2'></div><div id=c style='width:100px'></div></div></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    check(near(a.Width, 166.67, 0.1) && near(b.Width, 333.33, 0.1) && c.Width == 100, "flex grows into the free space by factor (got \(a.Width) \(b.Width) \(c.Width))")
    check(a.X == 0 && near(b.X, 166.67, 0.1) && near(c.X, 500, 0.1), "items sit side by side")
    check(a.Height == 100, "align-items: stretch fills the height")

    guard let j = layoutOf("<body style='margin:0'><div style='display:flex;width:600px;justify-content:space-between;align-items:center;height:100px'><div id=a style='width:100px;height:20px'></div><div id=b style='width:100px;height:40px'></div></div></body>") else { check(false, "layout"); return }
    check(j.rect("a")!.X == 0 && j.rect("b")!.X == 500, "justify-content: space-between")
    check(j.rect("a")!.Y == 40 && j.rect("b")!.Y == 30, "align-items: center (got \(j.rect("a")!.Y) \(j.rect("b")!.Y))")

    guard let col = layoutOf("<body style='margin:0'><div id=col style='display:flex;flex-direction:column;gap:10px;width:200px'><div id=a style='height:20px'></div><div id=b style='height:30px'></div></div></body>") else { check(false, "layout"); return }
    check(col.rect("b")!.Y == 30 && col.rect("col")!.Height == 60, "a column stacks with gaps and takes their height (got \(col.rect("b")!.Y) \(col.rect("col")!.Height))")
    check(col.rect("a")!.Width == 200, "column items stretch across")

    guard let wr = layoutOf("<body style='margin:0'><div id=w style='display:flex;flex-wrap:wrap;width:250px'><div id=a style='width:100px;height:10px'></div><div id=b style='width:100px;height:10px'></div><div id=c style='width:100px;height:10px'></div></div></body>") else { check(false, "layout"); return }
    check(wr.rect("c")!.Y == 10 && wr.rect("c")!.X == 0 && wr.rect("w")!.Height == 20, "flex-wrap wraps onto a second line")

    guard let sh = layoutOf("<body style='margin:0'><div style='display:flex;width:300px'><div id=a style='width:200px'></div><div id=b style='width:200px'></div></div></body>") else { check(false, "layout"); return }
    check(sh.rect("a")!.Width == 150 && sh.rect("b")!.Width == 150, "items shrink to fit (got \(sh.rect("a")!.Width))")

    guard let tx = layoutOf("<body style='margin:0'><div style='display:flex;width:400px'><div id=a>short</div><div id=b style='flex:1'>grows</div></div></body>") else { check(false, "layout"); return }
    let ta = tx.rect("a")!
    check(ta.Width > 20 && ta.Width < 60 && near(tx.rect("b")!.Width, 400 - ta.Width), "an item without flex takes its content width (got \(ta.Width))")
}

func testFloats() {
    print("Floats")
    guard let l = layoutOf("<body style='margin:0;font-size:16px;line-height:20px'><div id=f style='float:left;width:100px;height:50px'></div><div id=g style='float:right;width:80px;height:30px'></div><p id=p style='margin:0;width:400px'>one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty</p><div id=c style='clear:both;height:10px'></div></body>", width: 400) else { check(false, "layout"); return }
    let f = l.rect("f")!
    let g = l.rect("g")!
    check(f.X == 0 && f.Y == 0, "a left float sits at the left")
    check(g.X == 320 && g.Y == 0, "a right float sits at the right (got \(g.X) \(g.Y))")
    let p = l.box("p")!
    check(l.rect("p")!.Y == 0, "the paragraph starts where the floats do: floats take no flow height")
    let first = p.Lines[0]
    check(first.X == 100 && near(first.Width, 220), "the first line runs between the floats (x \(first.X) width \(first.Width))")
    var afterRight: Line? = nil
    var afterLeft: Line? = nil
    for line in p.Lines {
        if line.Y >= 30 && line.Y < 50 && afterRight == nil { afterRight = line }
        if line.Y >= 50 && afterLeft == nil { afterLeft = line }
    }
    let afterRightWidth: float32 = afterRight != nil ? afterRight!.Width : -1
    check(afterRight != nil && afterRight!.X == 100 && near(afterRightWidth, 300), "below the right float lines widen (got \(afterRightWidth))")
    check(afterLeft != nil && afterLeft!.X == 0 && near(afterLeft!.Width, 400), "below both floats lines take the full width")
    check(l.rect("c")!.Y >= 50, "clear: both moves below the floats (got \(l.rect("c")!.Y))")

    guard let s = layoutOf("<body style='margin:0'><div id=wrap style='overflow:hidden'><div id=a style='float:left;width:50px;height:40px'></div></div><div id=next style='height:5px'></div></body>") else { check(false, "layout"); return }
    check(s.rect("wrap")!.Height == 40, "a formatting root grows to hold its floats (got \(s.rect("wrap")!.Height))")
    check(s.rect("next")!.Y == 40, "and the next block comes after it")

    guard let i = layoutOf("<body style='margin:0;line-height:20px;width:300px'><p id=p style='margin:0'>text before <img id=img style='float:right;width:60px;height:30px'> and text after the image that keeps going and going and going for a while</p></body>", width: 300) else { check(false, "layout"); return }
    let img = i.rect("img")!
    check(img.X == 240 && img.Y == 0, "a float in text goes to the side at the top of its line (got \(img.X) \(img.Y))")
    let pl = i.box("p")!.Lines
    check(pl.count > 1 && near(pl[0].Width, 240) && pl[pl.count - 1].Width == 300, "lines beside the image are narrower, later ones full (got \(pl[0].Width) then \(pl[pl.count - 1].Width))")

    guard let two = layoutOf("<body style='margin:0'><div id=a style='float:left;width:100px;height:20px'></div><div id=b style='float:left;width:100px;height:20px'></div><div id=c style='float:left;width:100px;height:20px'></div></body>", width: 250) else { check(false, "layout"); return }
    check(two.rect("b")!.X == 100 && two.rect("c")!.X == 0 && two.rect("c")!.Y == 20, "floats line up and wrap when they do not fit (c at \(two.rect("c")!.X) \(two.rect("c")!.Y))")
}

func testTables() {
    print("Tables")
    guard let l = layoutOf("<body style='margin:0'><table id=t style='border-spacing:0'><tr><td id=a style='width:100px;height:20px;padding:0'>a</td><td id=b style='padding:0'>bb</td></tr><tr id=r2><td id=c style='padding:0'>c</td><td id=d style='padding:0;height:40px'>d</td></tr></table></body>") else { check(false, "layout"); return }
    let a = l.rect("a")!
    let b = l.rect("b")!
    let c = l.rect("c")!
    let d = l.rect("d")!
    check(a.X == 0 && b.X == 100, "cells sit side by side in their columns (b at \(b.X))")
    check(c.X == 0 && c.Width == 100, "a column is as wide as its widest cell (got \(c.Width))")
    check(c.Y == a.Height && c.Height == 40 && d.Height == 40, "a row is as tall as its tallest cell and cells stretch (c \(c.Y) \(c.Height))")
    check(b.Width > 10 && b.Width < 40, "an auto column fits its content (got \(b.Width))")
    let t = l.rect("t")!
    check(near(t.Width, 100 + b.Width) && near(t.Height, a.Height + 40), "the table shrinks to its columns and rows (got \(t.Width) x \(t.Height))")

    guard let w = layoutOf("<body style='margin:0'><table id=t style='width:400px;border-spacing:0'><tr><td id=a style='padding:0'>x</td><td id=b style='padding:0'>y</td></tr></table></body>") else { check(false, "layout"); return }
    check(w.rect("t")!.Width == 400 && near(w.rect("a")!.Width + w.rect("b")!.Width, 400), "a given width is shared by the columns (got \(w.rect("a")!.Width) + \(w.rect("b")!.Width))")

    guard let sp = layoutOf("<body style='margin:0'><table id=t style='border-spacing:4px'><tr><td id=a style='padding:0;width:50px;height:10px'></td><td id=b style='padding:0;width:50px'></td></tr></table></body>") else { check(false, "layout"); return }
    check(sp.rect("a")!.X == 4 && sp.rect("b")!.X == 58 && sp.rect("t")!.Width == 112, "border-spacing goes between and around cells (got \(sp.rect("a")!.X) \(sp.rect("b")!.X) \(sp.rect("t")!.Width))")

    guard let cs = layoutOf("<body style='margin:0'><table style='border-spacing:0'><tr><td id=wide colspan=2 style='padding:0'>wide</td></tr><tr><td id=a style='padding:0;width:60px'>a</td><td id=b style='padding:0;width:70px'>b</td></tr></table></body>") else { check(false, "layout"); return }
    check(cs.rect("wide")!.Width == 130, "a colspan cell spans its columns (got \(cs.rect("wide")!.Width))")

    guard let va = layoutOf("<body style='margin:0;line-height:20px'><table style='border-spacing:0'><tr><td id=tall style='padding:0;height:60px'></td><td id=mid style='padding:0;vertical-align:middle'>m</td><td id=top style='padding:0;vertical-align:top'>t</td></tr></table></body>") else { check(false, "layout"); return }
    let midLine = va.box("mid")!.Lines[0]
    let topLine = va.box("top")!.Lines[0]
    check(near(midLine.Y, 20) && topLine.Y == 0, "vertical-align middle centres a cell's content (got \(midLine.Y) and \(topLine.Y))")

    guard let tb = layoutOf("<body style='margin:0'><table id=t style='border-spacing:0'><thead id=h><tr><th id=th style='padding:0'>Head</th></tr></thead><tbody id=body><tr><td id=td style='padding:0'>cell</td></tr></tbody></table><p id=after style='margin:0'>x</p></body>") else { check(false, "layout"); return }
    check(tb.rect("td")!.Y == tb.rect("th")!.Height && tb.rect("body")!.Y == tb.rect("th")!.Height, "row groups stack (td at \(tb.rect("td")!.Y), tbody at \(tb.rect("body")!.Y))")
    check(tb.rect("after")!.Y == tb.rect("t")!.Height, "the table takes its rows' height in the flow")
    check(tb.box("th")!.Style.FontWeight == 700 && tb.box("th")!.Style.TextAlign == .center, "th is bold and centred by default")
}

func testWrapping() {
    print("Wrapping")
    let long = "averyveryveryveryveryverylongwordthatdoesnotfitonaline"
    guard let l = layoutOf("<body style='margin:0;font-size:16px'><p id=a style='margin:0;width:100px'>\(long) end</p><p id=b style='margin:0;width:100px;overflow-wrap:break-word'>\(long) end</p><p id=c style='margin:0;width:100px;word-break:break-all'>short words \(long)</p></body>") else { check(false, "layout"); return }
    let a = l.box("a")!
    check(a.Lines.count == 2 && a.Lines[0].Fragments[0].Width > 100, "a long word overflows by default (\(a.Lines.count) lines)")
    let b = l.box("b")!
    var widest: float32 = 0
    var pieces = 0
    for line in b.Lines {
        for f in line.Fragments {
            if f.X + f.Width > widest { widest = f.X + f.Width }
            pieces += 1
        }
    }
    check(b.Lines.count > 2 && widest <= 100.5, "overflow-wrap: break-word breaks the word across lines (\(b.Lines.count) lines, widest \(widest))")
    var joined = ""
    for line in b.Lines {
        for f in line.Fragments { joined += f.Text }
    }
    check(joined == long + " end" || joined == long + "end", "the pieces spell the word (got \(joined))")
    let c = l.box("c")!
    check(c.Lines.count > 2, "word-break: break-all breaks anywhere (\(c.Lines.count) lines)")

    guard let e = layoutOf("<body style='margin:0;font-size:16px'><p id=p style='margin:0;width:120px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis'>This sentence is far too long for the box</p></body>") else { check(false, "layout"); return }
    let line = e.box("p")!.Lines[0]
    let last = line.Fragments[line.Fragments.count - 1]
    check(last.Text.hasSuffix("…") && last.X + last.Width <= 120.5, "text-overflow: ellipsis cuts the line with an ellipsis (got \(last.Text))")
}

func testPseudoElements() {
    print("Pseudo-elements")
    guard let l = layoutOf("<style>p::before { content: '> '; color: red } a::after { content: ' (' attr(href) ')' } .clear::after { content: ''; display: block; clear: both; height: 5px }</style><body style='margin:0'><p id=p style='margin:0'>text</p><p id=q style='margin:0'><a href='x.html'>link</a></p><div class=clear id=c><div style='float:left;width:20px;height:30px'></div></div><div id=after></div></body>") else { check(false, "layout"); return }
    let p = l.box("p")!
    var joined = ""
    for f in p.Lines[0].Fragments { joined += f.Text }
    check(joined == "> text", "::before puts its content first (got '\(joined)')")
    check(p.Lines[0].Fragments[0].Owner.Style.Color == draw.Color(255, 0, 0), "the pseudo-element has its own style")
    let q = l.box("q")!
    joined = ""
    for f in q.Lines[0].Fragments { joined += f.Text }
    check(joined == "> link (x.html)", "::after with attr() reads the element's attribute (got '\(joined)')")
    check(l.rect("c")!.Height == 35 && l.rect("after")!.Y == l.rect("c")!.Y + 35, "a clearing ::after block contains the float (got \(l.rect("c")!.Height))")
}

func testPositioning() {
    print("Positioning")
    guard let l = layoutOf("<body style='margin:0'><div id=rel style='position:relative;width:300px;height:200px;margin-left:50px'><div id=abs style='position:absolute;top:10px;right:20px;width:100px;height:30px'></div><div id=full style='position:absolute;left:0;right:0;bottom:0;height:10px'></div></div><div id=fixed style='position:fixed;left:5px;top:6px;width:7px;height:8px'></div></body>") else { check(false, "layout"); return }
    let abs = l.rect("abs")!
    check(abs.X == 230 && abs.Y == 10, "absolute against the positioned ancestor's insets (got \(abs.X) \(abs.Y))")
    let full = l.rect("full")!
    check(full.Width == 300 && full.Y == 190, "left and right both set stretch the box (got \(full.Width) \(full.Y))")
    let fixed = l.rect("fixed")!
    check(fixed.X == 5 && fixed.Y == 6, "fixed against the viewport")
    let rel = l.box("rel")!
    check(rel.Positioned.count == 2, "the positioned ancestor keeps its positioned boxes")

    guard let r = layoutOf("<body style='margin:0'><div id=a style='height:10px'></div><div id=b style='position:relative;top:5px;left:8px;height:10px'></div><div id=c style='height:10px'></div></body>") else { check(false, "layout"); return }
    let b = r.box("b")!
    check(b.OffsetX == 8 && b.OffsetY == 5, "relative offsets are kept aside (got \(b.OffsetX) \(b.OffsetY))")
    check(r.rect("c")!.Y == 20, "relative positioning leaves the flow alone")
}

// MARK: - The view

func pixelAt(_ pixels: [uint8], _ w: int32, _ x: int32, _ y: int32) -> draw.Color {
    let i = int((y * w + x) * 4)
    return draw.Color(pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3])
}

func countDark(_ pixels: [uint8], _ w: int32, _ r: draw.IRect) -> int {
    var n = 0
    var y = r.Y
    while y < r.Bottom {
        var x = r.X
        while x < r.Right {
            let c = pixelAt(pixels, w, x, y)
            if int(c.R) + int(c.G) + int(c.B) < 300 { n += 1 }
            x += 1
        }
        y += 1
    }
    return n
}

@MainActor
func testView() {
    print("The view")
    let view = webview.WebView()
    view.SetBounds(origin: window.Point(0, 20), size: window.Size(300, 200))
    view.LoadHTML("""
    <title>Page One</title>
    <body style="margin:0">
      <div id=red style="background:red;width:100px;height:50px;border-radius:0"></div>
      <p id=text style="margin:10px 0;font-size:16px">Hello <a id=link href="page2.html">link</a></p>
      <div style="background:#00f;width:50px;height:20px;margin-left:100px"></div>
      <input id=field name=q value="ab">
      <button id=btn name=go value=1>Go</button>
      <div style="height:600px"></div>
    </body>
    """, baseURL: "/site/")
    check(view.Title == "Page One", "the title is read (got \(view.Title))")
    let w: int32 = 300
    let h: int32 = 240
    var pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 10, 30) == draw.Color(255, 0, 0), "the red box is painted at the view's origin (got \(pixelAt(pixels, w, 10, 30).R) \(pixelAt(pixels, w, 10, 30).G))")
    check(pixelAt(pixels, w, 150, 30) == draw.Color.white, "beside the box is the page background")
    check(pixelAt(pixels, w, 10, 5) == draw.Color(0, 0, 0, 0), "nothing is painted above the view")
    let p = view.BoxFor(view.QuerySelector("#text")!)!
    let textRow = draw.IRect(0, int32(p.Y + 20), 60, int32(p.Height))
    check(countDark(pixels, w, textRow) > 30, "text is painted (\(countDark(pixels, w, textRow)) dark pixels)")
    let blueY = int32(p.Y + p.Height + 20 + 15)
    check(pixelAt(pixels, w, 120, blueY) == draw.Color(0, 0, 255), "a later block lands below the paragraph (got y \(blueY))")
    check(view.ContentSize().Height > 600, "the content is taller than the view")
    check(!view.NeedsRepaint(), "drawing clears the repaint flag")

    // Hovering and clicking the link.
    let linkBox = view.BoxFor(view.QuerySelector("#link")!)!
    let linkRect = view.RootBox!.Lines.isEmpty ? draw.Rect.zero : draw.Rect.zero
    _ = linkRect
    var linkX: float32 = 0
    var linkY: float32 = 0
    for line in p.Lines {
        for sp in line.Spans {
            if sp.Box.Id == linkBox.Id {
                linkX = sp.X + sp.Width / 2
                linkY = line.Y + line.Height / 2
            }
        }
    }
    let over = window.Point(linkX, linkY + 20 + p.Y)
    _ = view.Handle(.pointerMoved(window.Pointer(Position: over)))
    check(view.DesiredCursor() == window.Cursor.pointingHand, "hovering a link asks for a hand (at \(over.X) \(over.Y))")
    var hovered: string? = "unset"
    view.OnHoverLink { url in hovered = url }
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(250, 30))))
    _ = view.Handle(.pointerMoved(window.Pointer(Position: over)))
    check(hovered == "/site/page2.html", "hovering reports the resolved link (got \(hovered ?? "nil"))")
    check(view.ElementAt(over)?.TagName == "a", "ElementAt finds the link")
    var navigated = ""
    view.OnNavigate { url in navigated = url }
    _ = view.Handle(.pointerDown(window.Pointer(Position: over), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: over), .primary))
    check(navigated == "/site/page2.html", "clicking the link navigates (got \(navigated))")
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(10, 30))))
    check(view.DesiredCursor() == window.Cursor.arrow, "off the link the cursor is an arrow")

    // Typing in the field.
    let field = view.QuerySelector("#field")!
    let fieldBox = view.BoxFor(field)!
    let fieldPos = window.Point(fieldBox.X + 5, fieldBox.Y + fieldBox.Height / 2 + 20)
    var fpX = fieldBox.X
    var fpY = fieldBox.Y
    var parent = fieldBox.Parent
    while let pb = parent { fpX += pb.X; fpY += pb.Y; parent = pb.Parent }
    let inField = window.Point(fpX + fieldBox.Width - 5, fpY + fieldBox.Height / 2 + 20)
    _ = fieldPos
    _ = view.Handle(.pointerDown(window.Pointer(Position: inField), .primary))
    _ = view.Handle(.pointerUp(window.Pointer(Position: inField), .primary))
    check(view.FocusedElement?.Id == field.Id, "clicking a field focuses it")
    _ = view.Handle(.text("c"))
    check(view.ValueOf(field) == "abc", "typing appends at the caret (got \(view.ValueOf(field)))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .arrowLeft, Key: "ArrowLeft", Modifiers: window.Modifiers(), Repeat: false)))
    _ = view.Handle(.text("X"))
    check(view.ValueOf(field) == "abXc", "the caret moves with the arrows (got \(view.ValueOf(field)))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .backspace, Key: "Backspace", Modifiers: window.Modifiers(), Repeat: false)))
    check(view.ValueOf(field) == "abc", "backspace deletes before the caret (got \(view.ValueOf(field)))")
    var action = ""
    view.OnAction { name, value in action = name + "=" + value }
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .enter, Key: "Enter", Modifiers: window.Modifiers(), Repeat: false)))
    check(action == "q=abc", "Enter in a field outside a form reports an action (got \(action))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .tab, Key: "Tab", Modifiers: window.Modifiers(), Repeat: false)))
    let focusedTag = view.FocusedElement?.TagName
    check(focusedTag == "button", "Tab moves focus to the button (got \(focusedTag ?? "nil"))")
    _ = view.Handle(.keyDown(window.KeyEvent(Code: .enter, Key: "Enter", Modifiers: window.Modifiers(), Repeat: false)))
    check(action == "go=1", "Enter on a button presses it (got \(action))")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(countDark(pixels, w, draw.IRect(int32(fpX), int32(fpY + 20), int32(fieldBox.Width), int32(fieldBox.Height))) > 10, "the field's text is painted")

    // Scrolling.
    _ = view.Handle(.pointerMoved(window.Pointer(Position: window.Point(150, 100))))
    _ = view.Handle(.scrolled(window.Scroll(Delta: window.Point(0, -3), Precise: false)))
    check(view.ScrollOffset().Y == 120, "a wheel step scrolls 40 points a line (got \(view.ScrollOffset().Y))")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 10, 30) == draw.Color.white, "after scrolling the red box has moved up out of view")
    _ = view.Handle(.scrolled(window.Scroll(Delta: window.Point(0, 100), Precise: false)))
    check(view.ScrollOffset().Y == 0, "scrolling up stops at the top")
    view.SetScrollOffset(window.Point(0, 10000))
    check(near(view.ScrollOffset().Y, view.ContentSize().Height - 200), "scrolling down stops at the bottom")

    // Resizing relayouts.
    view.SetBounds(origin: window.Point(0, 0), size: window.Size(150, 200))
    let narrow = view.BoxFor(view.QuerySelector("#text")!)!
    check(narrow.Width == 150, "a narrower view lays out narrower (got \(narrow.Width))")

    // Loading another page resets state.
    view.LoadHTML("<body style='margin:0;background:#123456'><h1>Two</h1></body>")
    check(view.ScrollOffset().Y == 0 && view.FocusedElement == nil, "a new page starts unscrolled and unfocused")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    view.Draw(into: &pixels, canvasSize: window.PixelSize(w, h), scale: 1)
    check(pixelAt(pixels, w, 140, 190) == draw.Color(0x12, 0x34, 0x56), "the body's background fills the view")

    // A select takes the keyboard.
    let sv = webview.WebView()
    sv.SetBounds(origin: window.Point(0, 0), size: window.Size(300, 100))
    sv.LoadHTML("<select id=s name=s><option>Alpha</option><option>Beta</option><option value=g>Gamma</option></select>")
    let selectNode = sv.QuerySelector("#s")!
    sv.Focus(selectNode)
    _ = sv.Handle(.keyDown(window.KeyEvent(Code: .arrowDown, Key: "ArrowDown", Modifiers: window.Modifiers(), Repeat: false)))
    check(sv.BoxFor(selectNode)!.Text == "Beta", "arrow down picks the next option (got \(sv.BoxFor(selectNode)!.Text))")
    _ = sv.Handle(.keyDown(window.KeyEvent(Code: .g, Key: "g", Modifiers: window.Modifiers(), Repeat: false)))
    check(sv.BoxFor(selectNode)!.Text == "Gamma", "a letter jumps to the option starting with it")
    _ = sv.Handle(.keyDown(window.KeyEvent(Code: .home, Key: "Home", Modifiers: window.Modifiers(), Repeat: false)))
    check(sv.BoxFor(selectNode)!.Text == "Alpha", "Home goes to the first option")

    // A sticky header follows the scroll within its container.
    let st = webview.WebView()
    st.SetBounds(origin: window.Point(0, 0), size: window.Size(300, 200))
    st.LoadHTML("<body style='margin:0'><div id=wrap style='height:600px'><div style='height:100px'></div><div id=h style='position:sticky;top:10px;height:20px'></div><div style='height:480px'></div></div><div style='height:1000px'></div></body>")
    var stPixels = [uint8](repeating: 0, count: 300 * 200 * 4)
    st.Draw(into: &stPixels, canvasSize: window.PixelSize(300, 200), scale: 1)
    let hBox = st.BoxFor(st.QuerySelector("#h")!)!
    check(hBox.OffsetY == 0, "unscrolled, a sticky box sits where it was laid out")
    st.SetScrollOffset(window.Point(0, 300))
    st.Draw(into: &stPixels, canvasSize: window.PixelSize(300, 200), scale: 1)
    check(near(hBox.OffsetY, 210), "scrolled past it, it sticks 10px below the top (offset \(hBox.OffsetY))")
    st.SetScrollOffset(window.Point(0, 590))
    st.Draw(into: &stPixels, canvasSize: window.PixelSize(300, 200), scale: 1)
    check(near(hBox.OffsetY, 480), "it stops at its container's end (offset \(hBox.OffsetY))")
    st.SetScrollOffset(window.Point(0, 0))
    st.Draw(into: &stPixels, canvasSize: window.PixelSize(300, 200), scale: 1)
    check(hBox.OffsetY == 0, "and comes back when scrolled up")

    // Selecting text by dragging.
    let sel = webview.WebView()
    sel.SetBounds(origin: window.Point(0, 0), size: window.Size(400, 200))
    sel.LoadHTML("<body style='margin:0;font-size:16px;line-height:20px'><p id=p style='margin:0'>alpha beta gamma</p><p id=q style='margin:0'>delta</p></body>")
    let pBox = sel.BoxFor(sel.QuerySelector("#p")!)!
    let frag = pBox.Lines[0].Fragments[0]
    let face = pBox.Style.Face
    let startX = frag.X + face.Measure("alpha ") + 1
    let endX = frag.X + face.Measure("alpha beta") - 1
    _ = sel.Handle(.pointerDown(window.Pointer(Position: window.Point(startX, 10)), .primary))
    _ = sel.Handle(.pointerMoved(window.Pointer(Position: window.Point(endX, 10))))
    _ = sel.Handle(.pointerUp(window.Pointer(Position: window.Point(endX, 10)), .primary))
    check(sel.SelectedText() == "beta", "dragging across a word selects it (got '\(sel.SelectedText())')")
    _ = sel.Handle(.pointerDown(window.Pointer(Position: window.Point(startX, 10)), .primary))
    _ = sel.Handle(.pointerMoved(window.Pointer(Position: window.Point(20, 30))))
    _ = sel.Handle(.pointerUp(window.Pointer(Position: window.Point(20, 30)), .primary))
    check(sel.SelectedText().hasPrefix("beta gamma\nde"), "a selection across lines breaks the line (got '\(sel.SelectedText())')")
    var px3 = [uint8](repeating: 0, count: 400 * 200 * 4)
    sel.Draw(into: &px3, canvasSize: window.PixelSize(400, 200), scale: 1)
    let hl = pixelAt(px3, 400, int32(frag.X + face.Measure("alpha beta")), 2)
    check(hl == draw.Color(179, 212, 252), "selected text is highlighted (got \(hl.R) \(hl.G) \(hl.B))")
    _ = sel.Handle(.pointerDown(window.Pointer(Position: window.Point(300, 150)), .primary))
    _ = sel.Handle(.pointerUp(window.Pointer(Position: window.Point(300, 150)), .primary))
    check(!sel.HasSelection, "clicking elsewhere clears the selection")
    sel.SelectAll()
    check(sel.SelectedText() == "alpha beta gamma\ndelta", "SelectAll takes the page's text (got '\(sel.SelectedText())')")

    // High-DPI: everything scales.
    let view2 = webview.WebView()
    view2.SetBounds(origin: window.Point(0, 0), size: window.Size(100, 100))
    view2.LoadHTML("<body style='margin:0'><div style='background:red;width:10px;height:10px'></div></body>")
    var px2 = [uint8](repeating: 0, count: 200 * 200 * 4)
    view2.Draw(into: &px2, canvasSize: window.PixelSize(200, 200), scale: 2)
    check(pixelAt(px2, 200, 19, 19) == draw.Color(255, 0, 0) && pixelAt(px2, 200, 21, 21) == draw.Color.white, "at 2x a 10px box is 20 pixels")
}

func main() -> int32 {
    testStyles()
    testBlockLayout()
    testInlineLayout()
    testFlexLayout()
    testPositioning()
    testFloats()
    testTables()
    testWrapping()
    testPseudoElements()
    testView()
    if failures == 0 {
        print("ALL WEBVIEW CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
