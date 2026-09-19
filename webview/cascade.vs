package webview

import "text/html"
import "text/css"
import "text/css/selector"
import "ui/draw"

/// One selector of one rule, with what the cascade sorts by.
final class StyleRule {
    let Selector: selector.ComplexSelector
    /// Specificity packed as ids, classes, tags, high to low.
    let Specificity: int32
    /// Where the rule stands in its origin's sheets: later wins ties.
    let Order: int32
    let Declarations: [Declaration]
    /// The media query the rule is under, or "" for none.
    let Media: string
    var enabled: bool = true

    init(selector sel: selector.ComplexSelector, order: int32, declarations: [Declaration], media: string) {
        Selector = sel
        let sp = sel.Specificity()
        Specificity = int32(sp.0) * 65536 + int32(sp.1) * 256 + int32(sp.2)
        Order = order
        Declarations = declarations
        Media = media
    }
}

/// The rules of one origin, bucketed by what their rightmost compound
/// asks for, so that an element is tested against the rules that could
/// match it and not against every rule on the page.
public final class RuleSet {
    var byId: [string: [StyleRule]] = [:]
    var byClass: [string: [StyleRule]] = [:]
    var byTag: [string: [StyleRule]] = [:]
    var universal: [StyleRule] = []
    var all: [StyleRule] = []
    var order: int32 = 0
    /// Whether any rule asks about pointer or keyboard state, which is
    /// what makes hovering or focusing worth a style recalculation.
    public var UsesHover: bool = false
    public var UsesFocus: bool = false
    public var UsesActive: bool = false
    var mediaWidth: float32 = -1
    var mediaHeight: float32 = -1

    public init() {}

    public var IsEmpty: bool { return all.isEmpty }

    /// Adds a stylesheet's rules, including those under @media.
    public func Add(_ sheet: css.StyleSheet) {
        for rule in sheet.Rules {
            add(rule, media: "")
        }
        for at in sheet.AtRules {
            if at.Name == "media" {
                for rule in at.Rules {
                    add(rule, media: lower(at.Params))
                }
            }
        }
    }

    func add(_ rule: css.Rule, media: string) {
        var decls: [Declaration] = []
        for d in rule.Declarations {
            decls.append(contentsOf: ParseDeclaration(d))
        }
        if decls.isEmpty { return }
        for text in rule.Selectors {
            let parsed = selector.ParseSelectors(text)
            for sel in parsed {
                order += 1
                let r = StyleRule(selector: sel, order: order, declarations: decls, media: media)
                noteState(sel)
                bucket(r)
            }
        }
    }

    func noteState(_ sel: selector.ComplexSelector) {
        for c in sel.Compounds {
            for p in c.Part.Pseudos {
                if p.Name == "hover" { UsesHover = true }
                if p.Name == "focus" || p.Name == "focus-within" || p.Name == "focus-visible" { UsesFocus = true }
                if p.Name == "active" { UsesActive = true }
                for inner in p.Inner { noteState(inner) }
            }
        }
    }

    func bucket(_ r: StyleRule) {
        all.append(r)
        let last = r.Selector.Compounds[r.Selector.Compounds.count - 1].Part
        if let id = last.Id {
            var list = byId[id] ?? []
            list.append(r)
            byId[id] = list
        } else if !last.Classes.isEmpty {
            var list = byClass[last.Classes[0]] ?? []
            list.append(r)
            byClass[last.Classes[0]] = list
        } else if let tag = last.Tag, tag != "*" {
            var list = byTag[tag] ?? []
            list.append(r)
            byTag[tag] = list
        } else {
            universal.append(r)
        }
    }

    /// Re-evaluates every @media rule for a viewport.
    func setViewport(_ width: float32, _ height: float32) {
        if width == mediaWidth && height == mediaHeight { return }
        mediaWidth = width
        mediaHeight = height
        for r in all {
            if !r.Media.isEmpty {
                r.enabled = mediaMatches(r.Media, width: width, height: height)
            }
        }
    }

    /// The rules that could match an element, by its tag, id and classes.
    func candidates(_ node: html.Node, into out: inout [StyleRule]) {
        for r in universal { if r.enabled { out.append(r) } }
        if let list = byTag[node.TagName] {
            for r in list { if r.enabled { out.append(r) } }
        }
        if let id = node.IdAttr() {
            if let list = byId[id] {
                for r in list { if r.enabled { out.append(r) } }
            }
        }
        if node.HasAttribute("class") {
            for cls in node.Classes() {
                if let list = byClass[cls] {
                    for r in list { if r.enabled { out.append(r) } }
                }
            }
        }
    }
}

/// Whether a media query holds for a viewport: `screen`, `all`,
/// `(min-width: N)`, `(max-width: N)`, `and`, `not`, and lists.
func mediaMatches(_ query: string, width: float32, height: float32) -> bool {
    for part in splitTop(query, on: 44) {
        if mediaClauseMatches(part, width: width, height: height) { return true }
    }
    return false
}

func mediaClauseMatches(_ clause: string, width: float32, height: float32) -> bool {
    let b = [uint8](clause.utf8)
    var i = 0
    var result = true
    var negate = false
    while i < b.count {
        while i < b.count && (b[i] == 32 || b[i] == 9) { i += 1 }
        if i >= b.count { break }
        if b[i] == 40 { // '('
            var depth = 1
            let start = i + 1
            i += 1
            while i < b.count && depth > 0 {
                if b[i] == 40 { depth += 1 }
                if b[i] == 41 { depth -= 1 }
                i += 1
            }
            let inner = draw.stringOf(b, start, i - 1)
            var ok = mediaFeature(inner, width: width, height: height)
            if negate { ok = !ok; negate = false }
            result = result && ok
            continue
        }
        let start = i
        while i < b.count && b[i] != 32 && b[i] != 40 { i += 1 }
        let word = draw.stringOf(b, start, i)
        switch word {
        case "and", "only": break
        case "not": negate = true
        case "screen", "all": if negate { result = false; negate = false }
        case "print", "speech", "aural", "braille", "tv", "projection", "handheld":
            if negate { negate = false } else { result = false }
        default: break
        }
    }
    return result
}

func mediaFeature(_ text: string, width: float32, height: float32) -> bool {
    var name = text
    var value = ""
    let b = [uint8](text.utf8)
    var i = 0
    while i < b.count && b[i] != 58 { i += 1 }
    if i < b.count {
        name = trimSpaces(draw.stringOf(b, 0, i))
        value = trimSpaces(draw.stringOf(b, i + 1, b.count))
    } else {
        name = trimSpaces(text)
    }
    let vb = [uint8](value.utf8)
    let number = draw.parseNumber(vb, 0, vb.count)
    var px = number
    if endsWith(value, "em") || endsWith(value, "rem") { px = number * 16 }
    switch name {
    case "min-width": return width >= px
    case "max-width": return width <= px
    case "min-height": return height >= px
    case "max-height": return height <= px
    case "width": return width == px
    case "orientation": return value == (width >= height ? "landscape" : "portrait")
    case "prefers-color-scheme": return value == "light"
    case "prefers-reduced-motion": return value == "no-preference"
    case "hover": return value == "hover"
    case "pointer": return value == "fine"
    case "min-resolution", "max-resolution", "resolution", "-webkit-min-device-pixel-ratio": return true
    case "color", "min-color", "display-mode", "forced-colors", "scripting": return name != "scripting" || value == "none"
    default: return false
    }
}

/// The candidate sorted by specificity then order, so that later,
/// more specific rules apply last and win.
func sortRules(_ rules: inout [StyleRule]) {
    var i = 1
    while i < rules.count {
        let r = rules[i]
        var j = i - 1
        while j >= 0 && (rules[j].Specificity > r.Specificity ||
                         (rules[j].Specificity == r.Specificity && rules[j].Order > r.Order)) {
            rules[j + 1] = rules[j]
            j -= 1
        }
        rules[j + 1] = r
        i += 1
    }
}

/// An element's inline style, parsed once per value of the attribute.
final class InlineStyle {
    let text: string
    let declarations: [Declaration]
    init(text: string, declarations: [Declaration]) {
        self.text = text
        self.declarations = declarations
    }
}

/// Computes styles: the user agent's rules, the page's, the element's
/// own attribute, in that order, sorted as the cascade sorts them.
public final class StyleResolver {
    public let UA: RuleSet
    public var Author: RuleSet
    public var ViewportWidth: float32 = 800
    public var ViewportHeight: float32 = 600
    public var RootFontSize: float32 = 16
    var inline: [int64: InlineStyle] = [:]
    var scratch: [StyleRule] = []

    public init(ua: RuleSet) {
        UA = ua
        Author = RuleSet()
    }

    /// Whether the page's rules react to the pointer or keyboard.
    public var UsesHover: bool { return Author.UsesHover || UA.UsesHover }
    public var UsesFocus: bool { return Author.UsesFocus || UA.UsesFocus }
    public var UsesActive: bool { return Author.UsesActive || UA.UsesActive }

    /// The style of an element, given its parent's.
    public func Resolve(_ node: html.Node, parent: ComputedStyle?, context: selector.MatchContext) -> ComputedStyle {
        UA.setViewport(ViewportWidth, ViewportHeight)
        Author.setViewport(ViewportWidth, ViewportHeight)
        let root = parent == nil
        let base = parent ?? defaultStyle
        let style = ComputedStyle(inheriting: base)
        let ctx = ApplyContext(parent: base, rootFontSize: root ? 16 : RootFontSize,
                               viewportWidth: ViewportWidth, viewportHeight: ViewportHeight)

        // Every declaration that applies, in cascade order: UA rules,
        // presentational attributes, author rules, the style attribute,
        // then the !important ones in the same order over again.
        var declarations: [Declaration] = []
        scratch.removeAll(keepingCapacity: true)
        UA.candidates(node, into: &scratch)
        var matched: [StyleRule] = []
        for r in scratch {
            if selector.MatchComplexIn(r.Selector, node, context) { matched.append(r) }
        }
        sortRules(&matched)
        for r in matched {
            for d in r.Declarations where !d.Important { declarations.append(d) }
        }
        let uaImportant = matched

        presentationalHints(node, into: &declarations)

        scratch.removeAll(keepingCapacity: true)
        Author.candidates(node, into: &scratch)
        matched = []
        for r in scratch {
            if selector.MatchComplexIn(r.Selector, node, context) { matched.append(r) }
        }
        sortRules(&matched)
        for r in matched {
            for d in r.Declarations where !d.Important { declarations.append(d) }
        }

        var inlineDecls: [Declaration] = []
        if let text = node.GetAttribute("style") {
            inlineDecls = inlineDeclarations(node, text)
            for d in inlineDecls where !d.Important { declarations.append(d) }
        }
        for r in matched {
            for d in r.Declarations where d.Important { declarations.append(d) }
        }
        for d in inlineDecls where d.Important { declarations.append(d) }
        for r in uaImportant {
            for d in r.Declarations where d.Important { declarations.append(d) }
        }

        // Font size first, since em lengths in the same element measure
        // against it whatever order the declarations came in.
        for d in declarations where d.Prop == .fontSize {
            apply(d, style, ctx)
        }
        for d in declarations where d.Prop != .fontSize {
            apply(d, style, ctx)
        }

        finish(style, node: node, root: root)
        if root {
            RootFontSize = style.FontSize
        }
        return style
    }

    /// The style text takes: its parent's, which is what inherits.
    public func ResolveText(parent: ComputedStyle) -> ComputedStyle {
        return parent
    }

    func inlineDeclarations(_ node: html.Node, _ text: string) -> [Declaration] {
        if let cached = inline[node.Id], cached.text == text {
            return cached.declarations
        }
        var decls: [Declaration] = []
        for d in css.ParseDeclarations(text) {
            decls.append(contentsOf: ParseDeclaration(d))
        }
        inline[node.Id] = InlineStyle(text: text, declarations: decls)
        return decls
    }

    /// What HTML attributes say about presentation, as the standard maps
    /// them to CSS: `hidden`, `width` and `height` on images and cells,
    /// `align`, `bgcolor`, `<font color>`, `<center>`.
    func presentationalHints(_ node: html.Node, into out: inout [Declaration]) {
        let tag = node.TagName
        if node.HasAttribute("hidden") {
            out.append(Declaration(.display, .keyword("none")))
        }
        if tag == "img" || tag == "video" || tag == "iframe" || tag == "canvas" || tag == "embed" || tag == "object" ||
            tag == "td" || tag == "th" || tag == "table" || tag == "col" || tag == "hr" {
            if let w = node.GetAttribute("width"), let v = dimensionAttribute(w) { out.append(Declaration(.width, v)) }
            if let h = node.GetAttribute("height"), let v = dimensionAttribute(h) { out.append(Declaration(.height, v)) }
        }
        if let align = node.GetAttribute("align") {
            let a = lower(align)
            if tag == "table" || tag == "img" {
                if a == "center" {
                    out.append(Declaration(.marginLeft, .auto))
                    out.append(Declaration(.marginRight, .auto))
                } else if a == "left" || a == "right" {
                    out.append(Declaration(.float, .keyword(a)))
                }
            } else if a == "left" || a == "right" || a == "center" || a == "justify" {
                out.append(Declaration(.textAlign, .keyword(a)))
            }
        }
        if let bg = node.GetAttribute("bgcolor"), let c = draw.Color.Parse(bg) {
            out.append(Declaration(.backgroundColor, .color(c)))
        }
        if tag == "font" {
            if let c = node.GetAttribute("color"), let col = draw.Color.Parse(c) {
                out.append(Declaration(.color, .color(col)))
            }
            if let s = node.GetAttribute("size") {
                let sizes: [float32] = [10, 13, 16, 18, 24, 32, 48]
                let b = [uint8](s.utf8)
                var n = int(draw.parseNumber(b, 0, b.count))
                if !b.isEmpty && (b[0] == 43 || b[0] == 45) { n = 3 + n }
                if n >= 1 && n <= 7 { out.append(Declaration(.fontSize, .length(sizes[n - 1], .px))) }
            }
        }
        if tag == "table" {
            if let border = node.GetAttribute("border"), !border.isEmpty && border != "0" {
                let b = [uint8](border.utf8)
                let w = draw.parseNumber(b, 0, b.count)
                for p in borderWidthProps { out.append(Declaration(p, .length(w > 0 ? w : 1, .px))) }
                for p in borderStyleProps { out.append(Declaration(p, .keyword("outset"))) }
            }
            if let spacing = node.GetAttribute("cellspacing") {
                let b = [uint8](spacing.utf8)
                out.append(Declaration(.borderSpacing, .length(draw.parseNumber(b, 0, b.count), .px)))
            }
        }
        if tag == "input" {
            if let type = node.GetAttribute("type"), lower(type) == "hidden" {
                out.append(Declaration(.display, .keyword("none")))
            }
        }
        if tag == "ol" {
            if let type = node.GetAttribute("type") {
                switch type {
                case "a": out.append(Declaration(.listStyleType, .keyword("lower-alpha")))
                case "A": out.append(Declaration(.listStyleType, .keyword("upper-alpha")))
                case "i": out.append(Declaration(.listStyleType, .keyword("lower-roman")))
                case "I": out.append(Declaration(.listStyleType, .keyword("upper-roman")))
                default: break
                }
            }
        }
    }

    func dimensionAttribute(_ text: string) -> Value? {
        let b = [uint8](trimSpaces(text).utf8)
        if b.isEmpty { return nil }
        let n = draw.parseNumber(b, 0, b.count)
        if b[b.count - 1] == 37 { return .length(n, .percent) }
        if n <= 0 && b[0] != 48 { return nil }
        return .length(n, .px)
    }

    /// What follows the cascade: borders without a style have no width,
    /// floats and positioned boxes are blocks, the root is a block.
    func finish(_ s: ComputedStyle, node: html.Node, root: bool) {
        if !s.BorderTopStyle.Draws { s.BorderTopWidth = 0 }
        if !s.BorderRightStyle.Draws { s.BorderRightWidth = 0 }
        if !s.BorderBottomStyle.Draws { s.BorderBottomWidth = 0 }
        if !s.BorderLeftStyle.Draws { s.BorderLeftWidth = 0 }
        if s.Display != .none {
            if s.Position == .absolute || s.Position == .fixed || s.Float != .none {
                s.Display = s.Display.Blockified
            }
            if root && s.Display.IsInlineLevel {
                s.Display = s.Display.Blockified
            }
        }
        if s.Position == .absolute || s.Position == .fixed {
            s.Float = .none
        }
        if s.OverflowX == .visible && s.OverflowY != .visible { s.OverflowX = .auto }
        if s.OverflowY == .visible && s.OverflowX != .visible { s.OverflowY = .auto }
    }
}

let defaultStyle = ComputedStyle()

/// What a declaration is applied against: the parent's style for
/// inheritance, the root font size for rem, the viewport for vw and vh.
struct ApplyContext {
    let parent: ComputedStyle
    let rootFontSize: float32
    let viewportWidth: float32
    let viewportHeight: float32
}

// MARK: - Applying declarations

func apply(_ d: Declaration, _ s: ComputedStyle, _ ctx: ApplyContext) {
    switch d.Value {
    case .inherit:
        copyProperty(d.Prop, from: ctx.parent, to: s)
        return
    case .initial:
        copyProperty(d.Prop, from: defaultStyle, to: s)
        return
    default:
        break
    }
    let v = d.Value
    switch d.Prop {
    case .display:
        if let k = keywordOf(v) { s.Display = displayOf(k) }
    case .position:
        if let k = keywordOf(v) {
            switch k {
            case "relative": s.Position = .relative
            case "absolute": s.Position = .absolute
            case "fixed": s.Position = .fixed
            case "sticky": s.Position = .sticky
            default: s.Position = .static
            }
        }
    case .float:
        if let k = keywordOf(v) {
            if k == "left" || k == "inline-start" { s.Float = .left }
            else if k == "right" || k == "inline-end" { s.Float = .right }
            else { s.Float = .none }
        }
    case .clear:
        if let k = keywordOf(v) {
            switch k {
            case "left", "inline-start": s.Clear = .left
            case "right", "inline-end": s.Clear = .right
            case "both": s.Clear = .both
            default: s.Clear = .none
            }
        }
    case .top: if let l = length(v, s, ctx) { s.Top = l }
    case .right: if let l = length(v, s, ctx) { s.Right = l }
    case .bottom: if let l = length(v, s, ctx) { s.Bottom = l }
    case .left: if let l = length(v, s, ctx) { s.Left = l }
    case .zIndex:
        if case .number(let n) = v { s.ZIndex = int32(n); s.HasZIndex = true }
        else { s.HasZIndex = false; s.ZIndex = 0 }
    case .width: if let l = length(v, s, ctx) { s.Width = l }
    case .height: if let l = length(v, s, ctx) { s.Height = l }
    case .minWidth: if let l = length(v, s, ctx) { s.MinWidth = l == .auto ? .px(0) : l }
    case .minHeight: if let l = length(v, s, ctx) { s.MinHeight = l == .auto ? .px(0) : l }
    case .maxWidth: if let l = length(v, s, ctx) { s.MaxWidth = l }
    case .maxHeight: if let l = length(v, s, ctx) { s.MaxHeight = l }
    case .boxSizing:
        if let k = keywordOf(v) { s.BoxSizing = k == "border-box" ? .borderBox : .contentBox }
    case .marginTop: if let l = length(v, s, ctx) { s.MarginTop = l }
    case .marginRight: if let l = length(v, s, ctx) { s.MarginRight = l }
    case .marginBottom: if let l = length(v, s, ctx) { s.MarginBottom = l }
    case .marginLeft: if let l = length(v, s, ctx) { s.MarginLeft = l }
    case .paddingTop: if let l = length(v, s, ctx) { s.PaddingTop = nonNegative(l) }
    case .paddingRight: if let l = length(v, s, ctx) { s.PaddingRight = nonNegative(l) }
    case .paddingBottom: if let l = length(v, s, ctx) { s.PaddingBottom = nonNegative(l) }
    case .paddingLeft: if let l = length(v, s, ctx) { s.PaddingLeft = nonNegative(l) }
    case .borderTopWidth: if let p = pixels(v, s, ctx) { s.BorderTopWidth = p }
    case .borderRightWidth: if let p = pixels(v, s, ctx) { s.BorderRightWidth = p }
    case .borderBottomWidth: if let p = pixels(v, s, ctx) { s.BorderBottomWidth = p }
    case .borderLeftWidth: if let p = pixels(v, s, ctx) { s.BorderLeftWidth = p }
    case .borderTopStyle: if let k = keywordOf(v) { s.BorderTopStyle = borderStyleOf(k) }
    case .borderRightStyle: if let k = keywordOf(v) { s.BorderRightStyle = borderStyleOf(k) }
    case .borderBottomStyle: if let k = keywordOf(v) { s.BorderBottomStyle = borderStyleOf(k) }
    case .borderLeftStyle: if let k = keywordOf(v) { s.BorderLeftStyle = borderStyleOf(k) }
    case .borderTopColor: s.BorderTopColor = colorOf(v)
    case .borderRightColor: s.BorderRightColor = colorOf(v)
    case .borderBottomColor: s.BorderBottomColor = colorOf(v)
    case .borderLeftColor: s.BorderLeftColor = colorOf(v)
    case .borderTopLeftRadius: if let p = pixels(v, s, ctx) { s.BorderRadius.TopLeft = p }
    case .borderTopRightRadius: if let p = pixels(v, s, ctx) { s.BorderRadius.TopRight = p }
    case .borderBottomRightRadius: if let p = pixels(v, s, ctx) { s.BorderRadius.BottomRight = p }
    case .borderBottomLeftRadius: if let p = pixels(v, s, ctx) { s.BorderRadius.BottomLeft = p }
    case .backgroundColor:
        if case .currentColor = v { s.BackgroundColor = s.Color }
        else if let c = colorOf(v) { s.BackgroundColor = c }
    case .backgroundImage:
        if case .url(let u) = v { s.BackgroundImage = BackgroundImage(url: u) } else { s.BackgroundImage = nil }
    case .opacity:
        if case .number(let n) = v { s.Opacity = n < 0 ? 0 : (n > 1 ? 1 : n) }
    case .overflowX: if let k = keywordOf(v) { s.OverflowX = overflowOf(k) }
    case .overflowY: if let k = keywordOf(v) { s.OverflowY = overflowOf(k) }
    case .boxShadow:
        if case .shadows(let list) = v {
            var out: [Shadow] = []
            for sh in list {
                out.append(Shadow(x: pixels(sh.X, s, ctx) ?? 0, y: pixels(sh.Y, s, ctx) ?? 0,
                                  blur: pixels(sh.Blur, s, ctx) ?? 0, spread: pixels(sh.Spread, s, ctx) ?? 0,
                                  color: sh.Color ?? s.Color, inset: sh.Inset))
            }
            s.Shadows = out
        } else {
            s.Shadows = []
        }
    case .outlineWidth: if let p = pixels(v, s, ctx) { s.OutlineWidth = p }
    case .outlineColor: s.OutlineColor = colorOf(v)
    case .verticalAlign:
        if let k = keywordOf(v) {
            switch k {
            case "middle": s.VerticalAlign = .middle
            case "top": s.VerticalAlign = .top
            case "bottom": s.VerticalAlign = .bottom
            case "text-top": s.VerticalAlign = .textTop
            case "text-bottom": s.VerticalAlign = .textBottom
            case "sub": s.VerticalAlign = .sub
            case "super": s.VerticalAlign = .super
            default: s.VerticalAlign = .baseline
            }
        } else if let l = length(v, s, ctx) {
            s.VerticalAlign = .length(l)
        }
    case .textDecorationLine:
        if let k = keywordOf(v) {
            var td = TextDecoration()
            for word in words(k) {
                if word == "underline" { td.Underline = true }
                if word == "overline" { td.Overline = true }
                if word == "line-through" { td.LineThrough = true }
            }
            s.TextDecoration = td
        }
    case .textDecorationColor: s.TextDecorationColor = colorOf(v)
    case .flexDirection:
        if let k = keywordOf(v) {
            switch k {
            case "row-reverse": s.FlexDirection = .rowReverse
            case "column": s.FlexDirection = .column
            case "column-reverse": s.FlexDirection = .columnReverse
            default: s.FlexDirection = .row
            }
        }
    case .flexWrap:
        if let k = keywordOf(v) {
            s.FlexWrap = k == "wrap" ? .wrap : (k == "wrap-reverse" ? .wrapReverse : .nowrap)
        }
    case .justifyContent: if let k = keywordOf(v) { s.JustifyContent = justifyOf(k) }
    case .alignContent: if let k = keywordOf(v) { s.AlignContent = justifyOf(k) }
    case .alignItems: if let k = keywordOf(v) { s.AlignItems = alignOf(k) }
    case .alignSelf: if let k = keywordOf(v) { s.AlignSelf = alignOf(k) }
    case .flexGrow: if case .number(let n) = v { s.FlexGrow = n < 0 ? 0 : n }
    case .flexShrink: if case .number(let n) = v { s.FlexShrink = n < 0 ? 0 : n }
    case .flexBasis: if let l = length(v, s, ctx) { s.FlexBasis = l }
    case .order: if case .number(let n) = v { s.Order = int32(n) } else { s.Order = 0 }
    case .rowGap: if let l = length(v, s, ctx) { s.RowGap = l }
    case .columnGap: if let l = length(v, s, ctx) { s.ColumnGap = l }
    case .tableLayout: if let k = keywordOf(v) { s.TableLayout = k == "fixed" ? .fixed : .auto }
    case .color:
        if case .currentColor = v { s.Color = ctx.parent.Color }
        else if let c = colorOf(v) { s.Color = c }
    case .fontFamily:
        if case .families(let list) = v { s.FontFamilies = list }
    case .fontSize:
        // em here is the parent's size: an element's own is what is
        // being decided.
        if case .length(let n, let unit) = v {
            switch unit {
            case .px: s.FontSize = n
            case .em: s.FontSize = ctx.parent.FontSize * n
            case .percent: s.FontSize = ctx.parent.FontSize * n / 100
            case .rem: s.FontSize = ctx.rootFontSize * n
            case .ex, .ch: s.FontSize = ctx.parent.FontSize * n * 0.5
            case .vw: s.FontSize = ctx.viewportWidth * n / 100
            case .vh: s.FontSize = ctx.viewportHeight * n / 100
            case .vmin: s.FontSize = minf(ctx.viewportWidth, ctx.viewportHeight) * n / 100
            case .vmax: s.FontSize = maxf(ctx.viewportWidth, ctx.viewportHeight) * n / 100
            }
            if s.FontSize < 0 { s.FontSize = 0 }
        }
    case .fontWeight:
        if case .number(let n) = v {
            s.FontWeight = int32(n)
        } else if let k = keywordOf(v) {
            switch k {
            case "bold": s.FontWeight = 700
            case "bolder": s.FontWeight = ctx.parent.FontWeight < 400 ? 400 : (ctx.parent.FontWeight < 600 ? 700 : 900)
            case "lighter": s.FontWeight = ctx.parent.FontWeight < 600 ? 100 : (ctx.parent.FontWeight < 800 ? 400 : 700)
            default: s.FontWeight = 400
            }
        }
    case .fontStyle:
        if let k = keywordOf(v) { s.FontStyle = k == "italic" ? .italic : (k == "oblique" ? .oblique : .normal) }
    case .lineHeight:
        switch v {
        case .normal: s.LineHeight = .normal
        case .number(let n): s.LineHeight = .number(n)
        default:
            if let p = pixels(v, s, ctx) { s.LineHeight = .px(p) }
        }
    case .textAlign:
        if let k = keywordOf(v) {
            switch k {
            case "left": s.TextAlign = .left
            case "right": s.TextAlign = .right
            case "center": s.TextAlign = .center
            case "justify": s.TextAlign = .justify
            case "end": s.TextAlign = .end
            default: s.TextAlign = .start
            }
        }
    case .textTransform:
        if let k = keywordOf(v) {
            switch k {
            case "uppercase": s.TextTransform = .uppercase
            case "lowercase": s.TextTransform = .lowercase
            case "capitalize": s.TextTransform = .capitalize
            default: s.TextTransform = .none
            }
        }
    case .textIndent: if let l = length(v, s, ctx) { s.TextIndent = l }
    case .letterSpacing:
        if case .normal = v { s.LetterSpacing = 0 } else if let p = pixels(v, s, ctx) { s.LetterSpacing = p }
    case .wordSpacing:
        if case .normal = v { s.WordSpacing = 0 } else if let p = pixels(v, s, ctx) { s.WordSpacing = p }
    case .whiteSpace:
        if let k = keywordOf(v) {
            switch k {
            case "nowrap": s.WhiteSpace = .nowrap
            case "pre": s.WhiteSpace = .pre
            case "pre-wrap": s.WhiteSpace = .preWrap
            case "pre-line": s.WhiteSpace = .preLine
            default: s.WhiteSpace = .normal
            }
        }
    case .listStyleType:
        if let k = keywordOf(v) {
            switch k {
            case "none": s.ListStyleType = .none
            case "circle": s.ListStyleType = .circle
            case "square": s.ListStyleType = .square
            case "decimal": s.ListStyleType = .decimal
            case "decimal-leading-zero": s.ListStyleType = .decimalLeadingZero
            case "lower-alpha", "lower-latin": s.ListStyleType = .lowerAlpha
            case "upper-alpha", "upper-latin": s.ListStyleType = .upperAlpha
            case "lower-roman": s.ListStyleType = .lowerRoman
            case "upper-roman": s.ListStyleType = .upperRoman
            default: s.ListStyleType = .disc
            }
        }
    case .listStylePosition:
        if let k = keywordOf(v) { s.ListStylePosition = k == "inside" ? .inside : .outside }
    case .cursor:
        if let k = keywordOf(v) {
            switch k {
            case "default": s.Cursor = .default
            case "pointer": s.Cursor = .pointer
            case "text": s.Cursor = .text
            case "crosshair": s.Cursor = .crosshair
            case "move", "grab", "grabbing": s.Cursor = k == "move" ? .move : .grab
            case "not-allowed": s.Cursor = .notAllowed
            case "ew-resize", "col-resize": s.Cursor = .ewResize
            case "ns-resize", "row-resize": s.Cursor = .nsResize
            case "wait", "progress": s.Cursor = .wait
            case "help": s.Cursor = .help
            case "none": s.Cursor = .none
            default: s.Cursor = .auto
            }
        }
    case .visibility:
        if let k = keywordOf(v) { s.Visibility = k == "hidden" ? .hidden : (k == "collapse" ? .collapse : .visible) }
    case .borderCollapse:
        if let k = keywordOf(v) { s.BorderCollapse = k == "collapse" ? .collapse : .separate }
    case .borderSpacing: if let p = pixels(v, s, ctx) { s.BorderSpacing = p }
    case .tabSize: if case .number(let n) = v { s.TabSize = int32(n) }
    }
}

func keywordOf(_ v: Value) -> string? {
    switch v {
    case .keyword(let k): return k
    case .auto: return "auto"
    case .none: return "none"
    case .normal: return "normal"
    default: return nil
    }
}

func colorOf(_ v: Value) -> draw.Color? {
    if case .color(let c) = v { return c }
    return nil
}

func words(_ s: string) -> [string] {
    var out: [string] = []
    let b = [uint8](s.utf8)
    var i = 0
    while i < b.count {
        while i < b.count && b[i] == 32 { i += 1 }
        let start = i
        while i < b.count && b[i] != 32 { i += 1 }
        if i > start { out.append(draw.stringOf(b, start, i)) }
    }
    return out
}

/// A length value resolved as far as the element allows: em, rem and
/// the viewport units to pixels; percentages left for layout.
func length(_ v: Value, _ s: ComputedStyle, _ ctx: ApplyContext) -> Length? {
    switch v {
    case .auto: return .auto
    case .none: return .none
    case .keyword(let k):
        switch k {
        case "min-content": return .minContent
        case "max-content": return .maxContent
        case "fit-content": return .fitContent
        default: return nil
        }
    case .length(let n, let unit):
        switch unit {
        case .px: return .px(n)
        case .percent: return .percent(n)
        case .em: return .px(n * s.FontSize)
        case .rem: return .px(n * ctx.rootFontSize)
        case .ex: return .px(n * s.FontSize * 0.5)
        case .ch: return .px(n * s.FontSize * 0.5)
        case .vw: return .px(n * ctx.viewportWidth / 100)
        case .vh: return .px(n * ctx.viewportHeight / 100)
        case .vmin: return .px(n * minf(ctx.viewportWidth, ctx.viewportHeight) / 100)
        case .vmax: return .px(n * maxf(ctx.viewportWidth, ctx.viewportHeight) / 100)
        }
    case .number(let n):
        return n == 0 ? .px(0) : nil
    default:
        return nil
    }
}

/// A length that must be pixels: borders, radii, spacing.
func pixels(_ v: Value, _ s: ComputedStyle, _ ctx: ApplyContext) -> float32? {
    guard let l = length(v, s, ctx) else { return nil }
    switch l {
    case .px(let p): return p
    case .percent(let p): return p * s.FontSize / 100
    default: return nil
    }
}

func nonNegative(_ l: Length) -> Length {
    switch l {
    case .px(let v): return v < 0 ? .px(0) : l
    case .percent(let p): return p < 0 ? .percent(0) : l
    default: return l
    }
}

func displayOf(_ k: string) -> Display {
    switch k {
    case "none": return .none
    case "block", "flow-root": return .block
    case "inline-block": return .inlineBlock
    case "flex", "grid": return .flex
    case "inline-flex", "inline-grid": return .inlineFlex
    case "list-item": return .listItem
    case "table": return .table
    case "inline-table": return .inlineTable
    case "table-row": return .tableRow
    case "table-cell": return .tableCell
    case "table-row-group": return .tableRowGroup
    case "table-header-group": return .tableHeaderGroup
    case "table-footer-group": return .tableFooterGroup
    case "table-caption": return .tableCaption
    case "table-column": return .tableColumn
    case "table-column-group": return .tableColumnGroup
    case "contents": return .contents
    default: return .inline
    }
}

func borderStyleOf(_ k: string) -> BorderStyle {
    switch k {
    case "hidden": return .hidden
    case "solid": return .solid
    case "dashed": return .dashed
    case "dotted": return .dotted
    case "double": return .double
    case "groove": return .groove
    case "ridge": return .ridge
    case "inset": return .inset
    case "outset": return .outset
    default: return .none
    }
}

func overflowOf(_ k: string) -> Overflow {
    switch k {
    case "hidden": return .hidden
    case "scroll": return .scroll
    case "auto": return .auto
    case "clip": return .clip
    default: return .visible
    }
}

func justifyOf(_ k: string) -> JustifyContent {
    switch k {
    case "flex-end", "end", "right": return .flexEnd
    case "center": return .center
    case "space-between": return .spaceBetween
    case "space-around": return .spaceAround
    case "space-evenly": return .spaceEvenly
    default: return .flexStart
    }
}

func alignOf(_ k: string) -> AlignItems {
    switch k {
    case "flex-start", "start", "self-start": return .flexStart
    case "flex-end", "end", "self-end": return .flexEnd
    case "center": return .center
    case "baseline": return .baseline
    case "auto": return .auto
    default: return .stretch
    }
}

/// Copies one property from one style to another: what `inherit` and
/// `initial` do.
func copyProperty(_ p: Prop, from a: ComputedStyle, to b: ComputedStyle) {
    switch p {
    case .display: b.Display = a.Display
    case .position: b.Position = a.Position
    case .float: b.Float = a.Float
    case .clear: b.Clear = a.Clear
    case .top: b.Top = a.Top
    case .right: b.Right = a.Right
    case .bottom: b.Bottom = a.Bottom
    case .left: b.Left = a.Left
    case .zIndex: b.ZIndex = a.ZIndex; b.HasZIndex = a.HasZIndex
    case .width: b.Width = a.Width
    case .height: b.Height = a.Height
    case .minWidth: b.MinWidth = a.MinWidth
    case .minHeight: b.MinHeight = a.MinHeight
    case .maxWidth: b.MaxWidth = a.MaxWidth
    case .maxHeight: b.MaxHeight = a.MaxHeight
    case .boxSizing: b.BoxSizing = a.BoxSizing
    case .marginTop: b.MarginTop = a.MarginTop
    case .marginRight: b.MarginRight = a.MarginRight
    case .marginBottom: b.MarginBottom = a.MarginBottom
    case .marginLeft: b.MarginLeft = a.MarginLeft
    case .paddingTop: b.PaddingTop = a.PaddingTop
    case .paddingRight: b.PaddingRight = a.PaddingRight
    case .paddingBottom: b.PaddingBottom = a.PaddingBottom
    case .paddingLeft: b.PaddingLeft = a.PaddingLeft
    case .borderTopWidth: b.BorderTopWidth = a.BorderTopWidth
    case .borderRightWidth: b.BorderRightWidth = a.BorderRightWidth
    case .borderBottomWidth: b.BorderBottomWidth = a.BorderBottomWidth
    case .borderLeftWidth: b.BorderLeftWidth = a.BorderLeftWidth
    case .borderTopStyle: b.BorderTopStyle = a.BorderTopStyle
    case .borderRightStyle: b.BorderRightStyle = a.BorderRightStyle
    case .borderBottomStyle: b.BorderBottomStyle = a.BorderBottomStyle
    case .borderLeftStyle: b.BorderLeftStyle = a.BorderLeftStyle
    case .borderTopColor: b.BorderTopColor = a.BorderTopColor
    case .borderRightColor: b.BorderRightColor = a.BorderRightColor
    case .borderBottomColor: b.BorderBottomColor = a.BorderBottomColor
    case .borderLeftColor: b.BorderLeftColor = a.BorderLeftColor
    case .borderTopLeftRadius: b.BorderRadius.TopLeft = a.BorderRadius.TopLeft
    case .borderTopRightRadius: b.BorderRadius.TopRight = a.BorderRadius.TopRight
    case .borderBottomRightRadius: b.BorderRadius.BottomRight = a.BorderRadius.BottomRight
    case .borderBottomLeftRadius: b.BorderRadius.BottomLeft = a.BorderRadius.BottomLeft
    case .backgroundColor: b.BackgroundColor = a.BackgroundColor
    case .backgroundImage: b.BackgroundImage = a.BackgroundImage
    case .opacity: b.Opacity = a.Opacity
    case .overflowX: b.OverflowX = a.OverflowX
    case .overflowY: b.OverflowY = a.OverflowY
    case .boxShadow: b.Shadows = a.Shadows
    case .outlineWidth: b.OutlineWidth = a.OutlineWidth
    case .outlineColor: b.OutlineColor = a.OutlineColor
    case .verticalAlign: b.VerticalAlign = a.VerticalAlign
    case .textDecorationLine: b.TextDecoration = a.TextDecoration
    case .textDecorationColor: b.TextDecorationColor = a.TextDecorationColor
    case .flexDirection: b.FlexDirection = a.FlexDirection
    case .flexWrap: b.FlexWrap = a.FlexWrap
    case .justifyContent: b.JustifyContent = a.JustifyContent
    case .alignItems: b.AlignItems = a.AlignItems
    case .alignSelf: b.AlignSelf = a.AlignSelf
    case .alignContent: b.AlignContent = a.AlignContent
    case .flexGrow: b.FlexGrow = a.FlexGrow
    case .flexShrink: b.FlexShrink = a.FlexShrink
    case .flexBasis: b.FlexBasis = a.FlexBasis
    case .order: b.Order = a.Order
    case .rowGap: b.RowGap = a.RowGap
    case .columnGap: b.ColumnGap = a.ColumnGap
    case .tableLayout: b.TableLayout = a.TableLayout
    case .color: b.Color = a.Color
    case .fontFamily: b.FontFamilies = a.FontFamilies
    case .fontSize: b.FontSize = a.FontSize
    case .fontWeight: b.FontWeight = a.FontWeight
    case .fontStyle: b.FontStyle = a.FontStyle
    case .lineHeight: b.LineHeight = a.LineHeight
    case .textAlign: b.TextAlign = a.TextAlign
    case .textTransform: b.TextTransform = a.TextTransform
    case .textIndent: b.TextIndent = a.TextIndent
    case .letterSpacing: b.LetterSpacing = a.LetterSpacing
    case .wordSpacing: b.WordSpacing = a.WordSpacing
    case .whiteSpace: b.WhiteSpace = a.WhiteSpace
    case .listStyleType: b.ListStyleType = a.ListStyleType
    case .listStylePosition: b.ListStylePosition = a.ListStylePosition
    case .cursor: b.Cursor = a.Cursor
    case .visibility: b.Visibility = a.Visibility
    case .borderCollapse: b.BorderCollapse = a.BorderCollapse
    case .borderSpacing: b.BorderSpacing = a.BorderSpacing
    case .tabSize: b.TabSize = a.TabSize
    }
}

func minf(_ a: float32, _ b: float32) -> float32 { return a < b ? a : b }
func maxf(_ a: float32, _ b: float32) -> float32 { return a > b ? a : b }

func trimSpaces(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && (b[start] == 32 || b[start] == 9 || b[start] == 10 || b[start] == 13) { start += 1 }
    while end > start && (b[end - 1] == 32 || b[end - 1] == 9 || b[end - 1] == 10 || b[end - 1] == 13) { end -= 1 }
    if start == 0 && end == b.count { return s }
    return draw.stringOf(b, start, end)
}

func endsWith(_ s: string, _ suffix: string) -> bool {
    return s.hasSuffix(suffix)
}

/// Splits on a byte outside parentheses.
func splitTop(_ s: string, on sep: uint8) -> [string] {
    var out: [string] = []
    let b = [uint8](s.utf8)
    var depth = 0
    var start = 0
    var i = 0
    while i < b.count {
        if b[i] == 40 { depth += 1 }
        if b[i] == 41 && depth > 0 { depth -= 1 }
        if b[i] == sep && depth == 0 {
            out.append(trimSpaces(draw.stringOf(b, start, i)))
            start = i + 1
        }
        i += 1
    }
    out.append(trimSpaces(draw.stringOf(b, start, b.count)))
    return out
}
