// The webview checked headless: styles, layout, painting, input.
package main

import "text/html"
import "text/css"
import "text/css/selector"
import "ui/draw"
import "ui/webview"

typealias Display = webview.Display

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
}

func main() -> int32 {
    testStyles()
    if failures == 0 {
        print("ALL WEBVIEW CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
