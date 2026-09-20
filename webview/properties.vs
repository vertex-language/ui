package webview

import "text/css"
import "ui/draw"

/// The properties the engine knows, each a longhand. Shorthands are
/// expanded into these when a declaration is parsed.
public enum Prop: int32 {
    case display = 1
    case position
    case float
    case clear
    case top
    case right
    case bottom
    case left
    case zIndex
    case width
    case height
    case minWidth
    case minHeight
    case maxWidth
    case maxHeight
    case boxSizing
    case marginTop
    case marginRight
    case marginBottom
    case marginLeft
    case paddingTop
    case paddingRight
    case paddingBottom
    case paddingLeft
    case borderTopWidth
    case borderRightWidth
    case borderBottomWidth
    case borderLeftWidth
    case borderTopStyle
    case borderRightStyle
    case borderBottomStyle
    case borderLeftStyle
    case borderTopColor
    case borderRightColor
    case borderBottomColor
    case borderLeftColor
    case borderTopLeftRadius
    case borderTopRightRadius
    case borderBottomRightRadius
    case borderBottomLeftRadius
    case backgroundColor
    case backgroundImage
    case backgroundRepeat
    case backgroundSize
    case backgroundPosition
    case opacity
    case overflowX
    case overflowY
    case boxShadow
    case outlineWidth
    case outlineColor
    case verticalAlign
    case textDecorationLine
    case textDecorationColor
    case flexDirection
    case flexWrap
    case justifyContent
    case alignItems
    case alignSelf
    case alignContent
    case flexGrow
    case flexShrink
    case flexBasis
    case order
    case rowGap
    case columnGap
    case tableLayout
    case color
    case fontFamily
    case fontSize
    case fontWeight
    case fontStyle
    case lineHeight
    case textAlign
    case textTransform
    case textIndent
    case letterSpacing
    case wordSpacing
    case whiteSpace
    case listStyleType
    case listStylePosition
    case cursor
    case visibility
    case borderCollapse
    case borderSpacing
    case tabSize
}

/// A unit a length was written in.
public enum Unit: Equatable {
    case px
    case em
    case rem
    case ex
    case ch
    case vw
    case vh
    case vmin
    case vmax
    case percent
}

/// A declaration's value as parsed: typed, but with lengths still in
/// their units, since em and rem depend on the element it lands on.
public enum Value {
    case auto
    case none
    case normal
    case length(float32, Unit)
    case number(float32)
    case keyword(string)
    case color(draw.Color)
    case currentColor
    case string(string)
    case families([string])
    case url(string)
    case gradient(draw.LinearGradient)
    case shadows([ShadowValue])
    case inherit
    case initial
}

/// A box-shadow before its lengths are resolved.
public struct ShadowValue {
    public var X: Value
    public var Y: Value
    public var Blur: Value
    public var Spread: Value
    public var Color: draw.Color?
    public var Inset: bool
}

/// One longhand and its value, as the cascade applies it.
public struct Declaration {
    public var Prop: Prop
    public var Value: Value
    public var Important: bool

    public init(_ prop: Prop, _ value: Value, important: bool = false) {
        self.Prop = prop
        self.Value = value
        self.Important = important
    }
}

let propNames: [string: Prop] = [
    "display": .display, "position": .position, "float": .float, "clear": .clear,
    "top": .top, "right": .right, "bottom": .bottom, "left": .left, "z-index": .zIndex,
    "width": .width, "height": .height, "min-width": .minWidth, "min-height": .minHeight,
    "max-width": .maxWidth, "max-height": .maxHeight, "box-sizing": .boxSizing,
    "margin-top": .marginTop, "margin-right": .marginRight, "margin-bottom": .marginBottom, "margin-left": .marginLeft,
    "padding-top": .paddingTop, "padding-right": .paddingRight, "padding-bottom": .paddingBottom, "padding-left": .paddingLeft,
    "border-top-width": .borderTopWidth, "border-right-width": .borderRightWidth,
    "border-bottom-width": .borderBottomWidth, "border-left-width": .borderLeftWidth,
    "border-top-style": .borderTopStyle, "border-right-style": .borderRightStyle,
    "border-bottom-style": .borderBottomStyle, "border-left-style": .borderLeftStyle,
    "border-top-color": .borderTopColor, "border-right-color": .borderRightColor,
    "border-bottom-color": .borderBottomColor, "border-left-color": .borderLeftColor,
    "border-top-left-radius": .borderTopLeftRadius, "border-top-right-radius": .borderTopRightRadius,
    "border-bottom-right-radius": .borderBottomRightRadius, "border-bottom-left-radius": .borderBottomLeftRadius,
    "background-color": .backgroundColor, "background-image": .backgroundImage, "opacity": .opacity,
    "background-repeat": .backgroundRepeat, "background-size": .backgroundSize, "background-position": .backgroundPosition,
    "overflow-x": .overflowX, "overflow-y": .overflowY, "box-shadow": .boxShadow,
    "outline-width": .outlineWidth, "outline-color": .outlineColor,
    "vertical-align": .verticalAlign, "text-decoration-line": .textDecorationLine,
    "text-decoration-color": .textDecorationColor,
    "flex-direction": .flexDirection, "flex-wrap": .flexWrap, "justify-content": .justifyContent,
    "align-items": .alignItems, "align-self": .alignSelf, "align-content": .alignContent,
    "flex-grow": .flexGrow, "flex-shrink": .flexShrink, "flex-basis": .flexBasis, "order": .order,
    "row-gap": .rowGap, "column-gap": .columnGap, "table-layout": .tableLayout,
    "color": .color, "font-family": .fontFamily, "font-size": .fontSize, "font-weight": .fontWeight,
    "font-style": .fontStyle, "line-height": .lineHeight, "text-align": .textAlign,
    "text-transform": .textTransform, "text-indent": .textIndent, "letter-spacing": .letterSpacing,
    "word-spacing": .wordSpacing, "white-space": .whiteSpace, "list-style-type": .listStyleType,
    "list-style-position": .listStylePosition, "cursor": .cursor, "visibility": .visibility,
    "border-collapse": .borderCollapse, "border-spacing": .borderSpacing, "tab-size": .tabSize,
]

/// Parses a declaration from a stylesheet into the longhands it sets.
/// A property the engine does not know, or a value it cannot read,
/// sets nothing, which is how a browser treats them too.
public func ParseDeclaration(_ d: css.Declaration) -> [Declaration] {
    let tokens = d.Tokens
    if tokens.isEmpty { return [] }
    let important = d.Important
    let name = d.Property

    // The keywords every property takes.
    if tokens.count == 1 && tokens[0].Kind == .ident {
        let kw = lower(tokens[0].Value)
        var wide: Value? = nil
        if kw == "inherit" { wide = .inherit }
        if kw == "initial" || kw == "unset" || kw == "revert" { wide = .initial }
        if let w = wide {
            var out: [Declaration] = []
            for p in longhandsOf(name) {
                out.append(Declaration(p, w, important: important))
            }
            return out
        }
    }

    if let prop = propNames[name] {
        if let v = parseValue(prop, tokens) {
            return [Declaration(prop, v, important: important)]
        }
        return []
    }

    var out: [Declaration] = []
    func set(_ p: Prop, _ v: Value) { out.append(Declaration(p, v, important: important)) }

    switch name {
    case "margin":
        guard let four = fourSides(tokens, allowAuto: true) else { return [] }
        set(.marginTop, four[0]); set(.marginRight, four[1]); set(.marginBottom, four[2]); set(.marginLeft, four[3])
    case "padding":
        guard let four = fourSides(tokens, allowAuto: false) else { return [] }
        set(.paddingTop, four[0]); set(.paddingRight, four[1]); set(.paddingBottom, four[2]); set(.paddingLeft, four[3])
    case "inset":
        guard let four = fourSides(tokens, allowAuto: true) else { return [] }
        set(.top, four[0]); set(.right, four[1]); set(.bottom, four[2]); set(.left, four[3])
    case "border-width":
        guard let four = fourValues(tokens, parseBorderWidth) else { return [] }
        set(.borderTopWidth, four[0]); set(.borderRightWidth, four[1]); set(.borderBottomWidth, four[2]); set(.borderLeftWidth, four[3])
    case "border-style":
        guard let four = fourValues(tokens, parseBorderStyle) else { return [] }
        set(.borderTopStyle, four[0]); set(.borderRightStyle, four[1]); set(.borderBottomStyle, four[2]); set(.borderLeftStyle, four[3])
    case "border-color":
        guard let four = fourValues(tokens, parseColorValue) else { return [] }
        set(.borderTopColor, four[0]); set(.borderRightColor, four[1]); set(.borderBottomColor, four[2]); set(.borderLeftColor, four[3])
    case "border", "border-top", "border-right", "border-bottom", "border-left":
        let parts = parseBorderShorthand(tokens)
        var sides: [int] = [0, 1, 2, 3]
        if name == "border-top" { sides = [0] } else if name == "border-right" { sides = [1] }
        else if name == "border-bottom" { sides = [2] } else if name == "border-left" { sides = [3] }
        for s in sides {
            set(borderWidthProps[s], parts.width)
            set(borderStyleProps[s], parts.style)
            set(borderColorProps[s], parts.color)
        }
    case "border-radius":
        // Horizontal radii only; what follows a slash is the same for
        // the round corners pages draw.
        var horizontal: [css.Token] = []
        for t in tokens {
            if t.Kind == .delim && t.Value == "/" { break }
            horizontal.append(t)
        }
        guard let four = fourSides(horizontal, allowAuto: false) else { return [] }
        set(.borderTopLeftRadius, four[0]); set(.borderTopRightRadius, four[1])
        set(.borderBottomRightRadius, four[2]); set(.borderBottomLeftRadius, four[3])
    case "background":
        // The first layer only: a color, an image or gradient, how it
        // repeats, where it sits, and after a slash how big it is.
        var i = 0
        var sawColor = false
        var sawImage = false
        var sawRepeat = false
        var sawSize = false
        var positions: [css.Token] = []
        var afterSlash = false
        while i < tokens.count {
            let t = tokens[i]
            if t.Kind == .comma { break }
            if t.Kind == .delim && t.Value == "/" { afterSlash = true; i += 1; continue }
            if let m = parseColorAt(tokens, i) {
                set(.backgroundColor, m.0)
                sawColor = true
                i += m.1
                continue
            }
            if t.Kind == .url {
                set(.backgroundImage, .url(t.Value))
                sawImage = true
            } else if t.Kind == .function && isGradientName(lower(t.Value)) {
                let end = closeParen(tokens, from: i + 1)
                if let g = parseGradient(tokens, i + 1, end) {
                    set(.backgroundImage, .gradient(g))
                    sawImage = true
                }
                i = end + 1
                continue
            } else if t.Kind == .ident {
                let kw = lower(t.Value)
                if kw == "no-repeat" || kw == "repeat" || kw == "repeat-x" || kw == "repeat-y" || kw == "space" || kw == "round" {
                    set(.backgroundRepeat, .keyword(kw))
                    sawRepeat = true
                } else if afterSlash && (kw == "cover" || kw == "contain" || kw == "auto") {
                    set(.backgroundSize, .keyword(kw))
                    sawSize = true
                } else if kw == "center" || kw == "left" || kw == "right" || kw == "top" || kw == "bottom" {
                    positions.append(t)
                }
            } else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number {
                if afterSlash {
                    var sizeTokens: [css.Token] = [t]
                    if i + 1 < tokens.count && (tokens[i + 1].Kind == .percentage || tokens[i + 1].Kind == .dimension || (tokens[i + 1].Kind == .ident && lower(tokens[i + 1].Value) == "auto")) {
                        sizeTokens.append(tokens[i + 1])
                        i += 1
                    }
                    if let v = parseBackgroundSize(sizeTokens) { set(.backgroundSize, v); sawSize = true }
                } else {
                    positions.append(t)
                }
            }
            i += 1
        }
        if !positions.isEmpty, let pos = parseBackgroundPosition(positions) { set(.backgroundPosition, pos) }
        else { set(.backgroundPosition, .initial) }
        if !sawColor { set(.backgroundColor, .initial) }
        if !sawImage { set(.backgroundImage, .none) }
        if !sawRepeat { set(.backgroundRepeat, .initial) }
        if !sawSize { set(.backgroundSize, .initial) }
    case "overflow":
        guard let first = parseOverflow(tokens[0]) else { return [] }
        set(.overflowX, first)
        set(.overflowY, tokens.count > 1 ? (parseOverflow(tokens[1]) ?? first) : first)
    case "font":
        parseFontShorthand(tokens, &out, important)
    case "flex":
        parseFlexShorthand(tokens, &out, important)
    case "flex-flow":
        for t in tokens {
            if let d = parseValue(.flexDirection, [t]) { set(.flexDirection, d) }
            else if let w = parseValue(.flexWrap, [t]) { set(.flexWrap, w) }
        }
    case "gap", "grid-gap":
        guard let first = parseLengthValue(tokens[0], allowAuto: false) else { return [] }
        set(.rowGap, first)
        set(.columnGap, tokens.count > 1 ? (parseLengthValue(tokens[1], allowAuto: false) ?? first) : first)
    case "list-style":
        for t in tokens {
            if let ty = parseValue(.listStyleType, [t]) { set(.listStyleType, ty) }
            else if let pos = parseValue(.listStylePosition, [t]) { set(.listStylePosition, pos) }
        }
    case "text-decoration":
        var i = 0
        var lines: [string] = []
        while i < tokens.count {
            if let m = parseColorAt(tokens, i) {
                set(.textDecorationColor, m.0)
                i += m.1
                continue
            }
            if tokens[i].Kind == .ident { lines.append(lower(tokens[i].Value)) }
            i += 1
        }
        if lines.isEmpty { lines = ["none"] }
        set(.textDecorationLine, .keyword(joinWords(lines)))
    case "outline":
        for t in tokens {
            if let w = parseBorderWidth(t) { set(.outlineWidth, w) }
            else if let m = parseColorAt([t], 0) { set(.outlineColor, m.0) }
        }
    case "place-items":
        if let v = parseValue(.alignItems, [tokens[0]]) { set(.alignItems, v) }
    case "text-decoration-style", "text-decoration-thickness", "text-underline-offset",
         "transition", "animation", "transform", "content", "quotes", "counter-reset", "counter-increment",
         "background-attachment",
         "font-variant", "font-stretch", "font-feature-settings", "src", "unicode-range",
         "grid-template-columns", "grid-template-rows", "grid-area", "grid-column", "grid-row",
         "user-select", "pointer-events", "appearance", "-webkit-appearance", "resize", "scroll-behavior",
         "text-rendering", "-webkit-font-smoothing", "-moz-osx-font-smoothing", "filter", "backdrop-filter",
         "clip-path", "object-fit", "aspect-ratio", "will-change", "contain", "isolation",
         "text-overflow", "word-break", "overflow-wrap", "word-wrap", "hyphens", "direction",
         "unicode-bidi", "writing-mode", "columns", "column-count", "column-width", "caption-side",
         "empty-cells", "speak", "orphans", "widows", "page-break-before", "page-break-after",
         "break-inside", "font-display", "text-shadow", "mix-blend-mode", "background-clip",
         "background-origin", "outline-offset", "outline-style", "border-image", "box-decoration-break",
         "text-size-adjust", "-webkit-text-size-adjust", "-webkit-tap-highlight-color", "touch-action",
         "overscroll-behavior", "scrollbar-width", "scrollbar-color", "list-style-image", "font-kerning",
         "text-align-last", "text-justify", "font-variant-numeric", "font-variant-ligatures",
         "font-optical-sizing", "color-scheme", "accent-color", "caret-color", "inset-inline",
         "inset-block", "margin-inline", "margin-block", "padding-inline", "padding-block",
         "border-inline", "border-block", "min-inline-size", "max-inline-size", "inline-size", "block-size",
         "place-content", "place-self", "justify-items", "justify-self", "grid", "grid-template",
         "grid-template-areas", "grid-auto-flow", "grid-auto-rows", "grid-auto-columns":
        break
    default:
        // margin-inline-start and friends, in a left-to-right, top-to-bottom world.
        if let mapped = logicalProp(name) {
            if let v = parseValue(mapped, tokens) { set(mapped, v) }
        }
    }
    return out
}

let borderWidthProps: [Prop] = [.borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth]
let borderStyleProps: [Prop] = [.borderTopStyle, .borderRightStyle, .borderBottomStyle, .borderLeftStyle]
let borderColorProps: [Prop] = [.borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor]

func logicalProp(_ name: string) -> Prop? {
    switch name {
    case "margin-inline-start": return .marginLeft
    case "margin-inline-end": return .marginRight
    case "margin-block-start": return .marginTop
    case "margin-block-end": return .marginBottom
    case "padding-inline-start": return .paddingLeft
    case "padding-inline-end": return .paddingRight
    case "padding-block-start": return .paddingTop
    case "padding-block-end": return .paddingBottom
    case "border-inline-start-width": return .borderLeftWidth
    case "border-inline-end-width": return .borderRightWidth
    case "border-start-start-radius": return .borderTopLeftRadius
    case "border-start-end-radius": return .borderTopRightRadius
    case "border-end-start-radius": return .borderBottomLeftRadius
    case "border-end-end-radius": return .borderBottomRightRadius
    case "inset-inline-start": return .left
    case "inset-inline-end": return .right
    case "inset-block-start": return .top
    case "inset-block-end": return .bottom
    default: return nil
    }
}

/// The longhands a property name stands for, for `inherit` and `initial`.
func longhandsOf(_ name: string) -> [Prop] {
    if let p = propNames[name] { return [p] }
    switch name {
    case "margin": return [.marginTop, .marginRight, .marginBottom, .marginLeft]
    case "padding": return [.paddingTop, .paddingRight, .paddingBottom, .paddingLeft]
    case "border-width": return borderWidthProps
    case "border-style": return borderStyleProps
    case "border-color": return borderColorProps
    case "border": return borderWidthProps + borderStyleProps + borderColorProps
    case "border-radius": return [.borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius]
    case "background": return [.backgroundColor, .backgroundImage, .backgroundRepeat, .backgroundSize, .backgroundPosition]
    case "overflow": return [.overflowX, .overflowY]
    case "font": return [.fontFamily, .fontSize, .fontWeight, .fontStyle, .lineHeight]
    case "flex": return [.flexGrow, .flexShrink, .flexBasis]
    case "gap": return [.rowGap, .columnGap]
    case "list-style": return [.listStyleType, .listStylePosition]
    case "text-decoration": return [.textDecorationLine, .textDecorationColor]
    default:
        if let p = logicalProp(name) { return [p] }
        return []
    }
}

// MARK: - Values

func lower(_ s: string) -> string {
    let b = [uint8](s.utf8)
    var i = 0
    var needs = false
    while i < b.count {
        if b[i] >= 65 && b[i] <= 90 { needs = true; break }
        i += 1
    }
    if !needs { return s }
    var out = b
    i = 0
    while i < out.count {
        if out[i] >= 65 && out[i] <= 90 { out[i] = out[i] + 32 }
        i += 1
    }
    return draw.stringOf(out, 0, out.count)
}

func joinWords(_ words: [string]) -> string {
    var out = ""
    var i = 0
    while i < words.count {
        if i > 0 { out += " " }
        out += words[i]
        i += 1
    }
    return out
}

func unitOf(_ s: string) -> Unit? {
    switch s {
    case "px": return .px
    case "em": return .em
    case "rem": return .rem
    case "ex": return .ex
    case "ch": return .ch
    case "vw": return .vw
    case "vh": return .vh
    case "vmin": return .vmin
    case "vmax": return .vmax
    default: return nil
    }
}

/// A length token as a value: px, relative units, absolute units scaled
/// to px, percentages, and unitless zero.
func parseLengthValue(_ t: css.Token, allowAuto: Bool) -> Value? {
    switch t.Kind {
    case .dimension:
        if let u = unitOf(t.Unit) { return .length(t.NumberVal, u) }
        switch t.Unit {
        case "pt": return .length(t.NumberVal * 4 / 3, .px)
        case "pc": return .length(t.NumberVal * 16, .px)
        case "in": return .length(t.NumberVal * 96, .px)
        case "cm": return .length(t.NumberVal * 96 / 2.54, .px)
        case "mm": return .length(t.NumberVal * 96 / 25.4, .px)
        case "q": return .length(t.NumberVal * 96 / 101.6, .px)
        default: return nil
        }
    case .percentage:
        return .length(t.NumberVal, .percent)
    case .number:
        if t.NumberVal == 0 { return .length(0, .px) }
        return nil
    case .ident:
        let kw = lower(t.Value)
        if kw == "auto" && allowAuto { return .auto }
        if kw == "min-content" || kw == "max-content" || kw == "fit-content" { return .keyword(kw) }
        return nil
    case .function:
        return nil
    default:
        return nil
    }
}

/// One to four lengths, as the sides shorthands take them.
func fourSides(_ tokens: [css.Token], allowAuto: Bool) -> [Value]? {
    return fourValues(tokens) { t in parseLengthValue(t, allowAuto: allowAuto) }
}

func fourValues(_ tokens: [css.Token], _ parse: (css.Token) -> Value?) -> [Value]? {
    var vals: [Value] = []
    for t in tokens {
        guard let v = parse(t) else { return nil }
        vals.append(v)
        if vals.count == 4 { break }
    }
    switch vals.count {
    case 1: return [vals[0], vals[0], vals[0], vals[0]]
    case 2: return [vals[0], vals[1], vals[0], vals[1]]
    case 3: return [vals[0], vals[1], vals[2], vals[1]]
    case 4: return vals
    default: return nil
    }
}

func parseBorderWidth(_ t: css.Token) -> Value? {
    if t.Kind == .ident {
        switch lower(t.Value) {
        case "thin": return .length(1, .px)
        case "medium": return .length(3, .px)
        case "thick": return .length(5, .px)
        default: return nil
        }
    }
    if t.Kind == .percentage { return nil }
    return parseLengthValue(t, allowAuto: false)
}

func parseBorderStyle(_ t: css.Token) -> Value? {
    if t.Kind != .ident { return nil }
    switch lower(t.Value) {
    case "none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset":
        return .keyword(lower(t.Value))
    default:
        return nil
    }
}

/// A color at tokens[i], and how many tokens it took; nil where there
/// is none there.
func parseColorAt(_ tokens: [css.Token], _ i: int) -> (Value, int)? {
    let t = tokens[i]
    switch t.Kind {
    case .hash:
        if let c = draw.Color.Parse(t.Value) { return (Value.color(c), 1) }
        return nil
    case .ident:
        let kw = lower(t.Value)
        if kw == "currentcolor" { return (Value.currentColor, 1) }
        if kw == "transparent" { return (Value.color(draw.Color.transparent), 1) }
        if let c = draw.Color.Parse(kw) { return (Value.color(c), 1) }
        return nil
    case .function:
        let name = lower(t.Value)
        if name != "rgb" && name != "rgba" && name != "hsl" && name != "hsla" { return nil }
        var j = i + 1
        var depth = 1
        var inner: [css.Token] = []
        while j < tokens.count {
            if tokens[j].Kind == .function || tokens[j].Kind == .openParen { depth += 1 }
            if tokens[j].Kind == .closeParen {
                depth -= 1
                if depth == 0 { break }
            }
            inner.append(tokens[j])
            j += 1
        }
        let text = name + "(" + css.Serialize(inner) + ")"
        if let c = draw.Color.Parse(text) { return (Value.color(c), j - i + 1) }
        return nil
    default:
        return nil
    }
}

func parseColorValue(_ t: css.Token) -> Value? {
    if let m = parseColorAt([t], 0) { return m.0 }
    return nil
}

func parseOverflow(_ t: css.Token) -> Value? {
    if t.Kind != .ident { return nil }
    switch lower(t.Value) {
    case "visible", "hidden", "scroll", "auto", "clip", "overlay":
        return .keyword(lower(t.Value) == "overlay" ? "auto" : lower(t.Value))
    default: return nil
    }
}

struct BorderParts {
    var width: Value = .initial
    var style: Value = .initial
    var color: Value = .initial
}

func parseBorderShorthand(_ tokens: [css.Token]) -> BorderParts {
    var parts = BorderParts()
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if let s = parseBorderStyle(t) {
            parts.style = s
        } else if let w = parseBorderWidth(t) {
            parts.width = w
        } else if let m = parseColorAt(tokens, i) {
            parts.color = m.0
            i += m.1
            continue
        }
        i += 1
    }
    return parts
}

func parseFontShorthand(_ tokens: [css.Token], _ out: inout [Declaration], _ important: Bool) {
    // [style || weight]* size [/ line-height]? family
    var i = 0
    var style: Value = .initial
    var weight: Value = .initial
    var size: Value? = nil
    var lineHeight: Value = .initial
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .ident {
            let kw = lower(t.Value)
            if kw == "italic" || kw == "oblique" { style = .keyword(kw); i += 1; continue }
            if kw == "bold" || kw == "bolder" || kw == "lighter" { weight = .keyword(kw); i += 1; continue }
            if kw == "normal" || kw == "small-caps" { i += 1; continue }
            if let s = parseFontSizeValue(t) { size = s; i += 1; break }
            // A bare family name is where the family list starts.
            break
        }
        if t.Kind == .number && (t.NumberVal == 100 || t.NumberVal == 200 || t.NumberVal == 300 || t.NumberVal == 400 ||
            t.NumberVal == 500 || t.NumberVal == 600 || t.NumberVal == 700 || t.NumberVal == 800 || t.NumberVal == 900) {
            weight = .number(t.NumberVal)
            i += 1
            continue
        }
        if let s = parseFontSizeValue(t) { size = s; i += 1; break }
        i += 1
    }
    guard let sz = size else { return }
    if i < tokens.count && tokens[i].Kind == .delim && tokens[i].Value == "/" {
        i += 1
        if i < tokens.count {
            if let lh = parseLineHeightValue(tokens[i]) { lineHeight = lh }
            i += 1
        }
    }
    var rest: [css.Token] = []
    while i < tokens.count {
        rest.append(tokens[i])
        i += 1
    }
    out.append(Declaration(.fontStyle, style, important: important))
    out.append(Declaration(.fontWeight, weight, important: important))
    out.append(Declaration(.fontSize, sz, important: important))
    out.append(Declaration(.lineHeight, lineHeight, important: important))
    if !rest.isEmpty {
        out.append(Declaration(.fontFamily, .families(parseFamilies(rest)), important: important))
    }
}

func parseFlexShorthand(_ tokens: [css.Token], _ out: inout [Declaration], _ important: Bool) {
    var grow: Value = .number(1)
    var shrink: Value = .number(1)
    var basis: Value = .length(0, .px)
    if tokens.count == 1 && tokens[0].Kind == .ident {
        switch lower(tokens[0].Value) {
        case "none": grow = .number(0); shrink = .number(0); basis = .auto
        case "auto": grow = .number(1); shrink = .number(1); basis = .auto
        case "initial": grow = .number(0); shrink = .number(1); basis = .auto
        default: return
        }
    } else {
        var numbers: [float32] = []
        for t in tokens {
            if t.Kind == .number {
                numbers.append(t.NumberVal)
            } else if let l = parseLengthValue(t, allowAuto: true) {
                basis = l
            }
        }
        if numbers.count >= 1 { grow = .number(numbers[0]) }
        if numbers.count >= 2 { shrink = .number(numbers[1]) }
    }
    out.append(Declaration(.flexGrow, grow, important: important))
    out.append(Declaration(.flexShrink, shrink, important: important))
    out.append(Declaration(.flexBasis, basis, important: important))
}

func parseFontSizeValue(_ t: css.Token) -> Value? {
    if t.Kind == .ident {
        switch lower(t.Value) {
        case "xx-small": return .length(9, .px)
        case "x-small": return .length(10, .px)
        case "small": return .length(13, .px)
        case "medium": return .length(16, .px)
        case "large": return .length(18, .px)
        case "x-large": return .length(24, .px)
        case "xx-large": return .length(32, .px)
        case "xxx-large": return .length(48, .px)
        case "smaller": return .length(0.8333, .em)
        case "larger": return .length(1.2, .em)
        default: return nil
        }
    }
    if t.Kind == .number && t.NumberVal != 0 { return nil }
    return parseLengthValue(t, allowAuto: false)
}

func parseLineHeightValue(_ t: css.Token) -> Value? {
    if t.Kind == .ident && lower(t.Value) == "normal" { return .normal }
    if t.Kind == .number { return .number(t.NumberVal) }
    return parseLengthValue(t, allowAuto: false)
}

/// Family names, comma-separated; a quoted name is one token, an
/// unquoted one may be several.
func parseFamilies(_ tokens: [css.Token]) -> [string] {
    var out: [string] = []
    var current: [string] = []
    for t in tokens {
        if t.Kind == .comma {
            if !current.isEmpty { out.append(joinWords(current)) }
            current = []
        } else if t.Kind == .string {
            current.append(t.Value)
        } else if t.Kind == .ident {
            current.append(t.Value)
        }
    }
    if !current.isEmpty { out.append(joinWords(current)) }
    return out
}

func parseShadows(_ tokens: [css.Token]) -> Value? {
    if tokens.count == 1 && tokens[0].Kind == .ident && lower(tokens[0].Value) == "none" { return .none }
    var shadows: [ShadowValue] = []
    var lengths: [Value] = []
    var color: draw.Color? = nil
    var inset = false
    func flush() {
        if lengths.count >= 2 {
            shadows.append(ShadowValue(X: lengths[0], Y: lengths[1],
                                       Blur: lengths.count > 2 ? lengths[2] : .length(0, .px),
                                       Spread: lengths.count > 3 ? lengths[3] : .length(0, .px),
                                       Color: color, Inset: inset))
        }
        lengths = []
        color = nil
        inset = false
    }
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t.Kind == .comma {
            flush()
            i += 1
            continue
        }
        if t.Kind == .ident && lower(t.Value) == "inset" {
            inset = true
            i += 1
            continue
        }
        if let m = parseColorAt(tokens, i) {
            if case .color(let cc) = m.0 { color = cc }
            i += m.1
            continue
        }
        if let l = parseLengthValue(t, allowAuto: false) {
            lengths.append(l)
        }
        i += 1
    }
    flush()
    if shadows.isEmpty { return nil }
    return .shadows(shadows)
}

/// The value of one longhand, read from its tokens.
func parseValue(_ prop: Prop, _ tokens: [css.Token]) -> Value? {
    let t = tokens[0]
    let kw = t.Kind == .ident ? lower(t.Value) : ""
    switch prop {
    case .display:
        switch kw {
        case "none", "block", "inline", "inline-block", "flex", "inline-flex", "list-item", "table",
             "inline-table", "table-row", "table-cell", "table-row-group", "table-header-group",
             "table-footer-group", "table-caption", "table-column", "table-column-group", "contents",
             "grid", "inline-grid", "flow-root":
            return .keyword(kw)
        default: return nil
        }
    case .position:
        switch kw {
        case "static", "relative", "absolute", "fixed", "sticky": return .keyword(kw)
        default: return nil
        }
    case .float:
        switch kw {
        case "none", "left", "right", "inline-start", "inline-end": return .keyword(kw)
        default: return nil
        }
    case .clear:
        switch kw {
        case "none", "left", "right", "both", "inline-start", "inline-end": return .keyword(kw)
        default: return nil
        }
    case .top, .right, .bottom, .left, .width, .height, .flexBasis:
        return parseLengthValue(t, allowAuto: true)
    case .minWidth, .minHeight:
        if kw == "auto" { return .auto }
        return parseLengthValue(t, allowAuto: false)
    case .maxWidth, .maxHeight:
        if kw == "none" { return .none }
        return parseLengthValue(t, allowAuto: false)
    case .marginTop, .marginRight, .marginBottom, .marginLeft:
        return parseLengthValue(t, allowAuto: true)
    case .paddingTop, .paddingRight, .paddingBottom, .paddingLeft, .textIndent, .rowGap, .columnGap:
        return parseLengthValue(t, allowAuto: false)
    case .borderTopWidth, .borderRightWidth, .borderBottomWidth, .borderLeftWidth, .outlineWidth:
        return parseBorderWidth(t)
    case .borderTopStyle, .borderRightStyle, .borderBottomStyle, .borderLeftStyle:
        return parseBorderStyle(t)
    case .borderTopColor, .borderRightColor, .borderBottomColor, .borderLeftColor,
         .backgroundColor, .color, .textDecorationColor, .outlineColor:
        if let m = parseColorAt(tokens, 0) { return m.0 }
        return nil
    case .borderTopLeftRadius, .borderTopRightRadius, .borderBottomRightRadius, .borderBottomLeftRadius:
        return parseLengthValue(t, allowAuto: false)
    case .backgroundImage:
        if kw == "none" { return .none }
        if t.Kind == .url { return .url(t.Value) }
        if t.Kind == .function && isGradientName(lower(t.Value)) {
            if let g = parseGradient(tokens, 1, closeParen(tokens, from: 1)) { return .gradient(g) }
        }
        return nil
    case .backgroundRepeat:
        switch kw {
        case "no-repeat", "repeat", "repeat-x", "repeat-y", "space", "round": return .keyword(kw)
        default: return nil
        }
    case .backgroundSize:
        if kw == "cover" || kw == "contain" || kw == "auto" { return .keyword(kw) }
        return parseBackgroundSize(tokens)
    case .backgroundPosition:
        return parseBackgroundPosition(tokens)
    case .opacity, .flexGrow, .flexShrink:
        if t.Kind == .number { return .number(t.NumberVal) }
        if t.Kind == .percentage && prop == .opacity { return .number(t.NumberVal / 100) }
        return nil
    case .zIndex, .order, .tabSize:
        if kw == "auto" { return .auto }
        if t.Kind == .number { return .number(t.NumberVal) }
        return nil
    case .overflowX, .overflowY:
        return parseOverflow(t)
    case .boxShadow:
        return parseShadows(tokens)
    case .verticalAlign:
        switch kw {
        case "baseline", "middle", "top", "bottom", "text-top", "text-bottom", "sub", "super": return .keyword(kw)
        default: return parseLengthValue(t, allowAuto: false)
        }
    case .textDecorationLine:
        var words: [string] = []
        for tok in tokens {
            if tok.Kind == .ident { words.append(lower(tok.Value)) }
        }
        return .keyword(joinWords(words))
    case .flexDirection:
        switch kw {
        case "row", "row-reverse", "column", "column-reverse": return .keyword(kw)
        default: return nil
        }
    case .flexWrap:
        switch kw {
        case "nowrap", "wrap", "wrap-reverse": return .keyword(kw)
        default: return nil
        }
    case .justifyContent, .alignContent:
        switch kw {
        case "flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly",
             "start", "end", "left", "right", "normal", "stretch":
            return .keyword(kw)
        default: return nil
        }
    case .alignItems, .alignSelf:
        switch kw {
        case "stretch", "flex-start", "flex-end", "center", "baseline", "auto", "start", "end", "normal", "self-start", "self-end":
            return .keyword(kw)
        default: return nil
        }
    case .tableLayout:
        if kw == "auto" || kw == "fixed" { return .keyword(kw) }
        return nil
    case .boxSizing:
        if kw == "content-box" || kw == "border-box" { return .keyword(kw) }
        return nil
    case .fontFamily:
        let fams = parseFamilies(tokens)
        return fams.isEmpty ? nil : .families(fams)
    case .fontSize:
        return parseFontSizeValue(t)
    case .fontWeight:
        if t.Kind == .number { return .number(t.NumberVal) }
        switch kw {
        case "normal", "bold", "bolder", "lighter": return .keyword(kw)
        default: return nil
        }
    case .fontStyle:
        switch kw {
        case "normal", "italic", "oblique": return .keyword(kw)
        default: return nil
        }
    case .lineHeight:
        return parseLineHeightValue(t)
    case .textAlign:
        switch kw {
        case "left", "right", "center", "justify", "start", "end", "-webkit-center": return .keyword(kw == "-webkit-center" ? "center" : kw)
        default: return nil
        }
    case .textTransform:
        switch kw {
        case "none", "uppercase", "lowercase", "capitalize": return .keyword(kw)
        default: return nil
        }
    case .letterSpacing, .wordSpacing:
        if kw == "normal" { return .normal }
        return parseLengthValue(t, allowAuto: false)
    case .whiteSpace:
        switch kw {
        case "normal", "nowrap", "pre", "pre-wrap", "pre-line", "break-spaces": return .keyword(kw == "break-spaces" ? "pre-wrap" : kw)
        default: return nil
        }
    case .listStyleType:
        switch kw {
        case "none", "disc", "circle", "square", "decimal", "decimal-leading-zero", "lower-alpha", "upper-alpha",
             "lower-latin", "upper-latin", "lower-roman", "upper-roman":
            return .keyword(kw)
        default: return nil
        }
    case .listStylePosition:
        if kw == "inside" || kw == "outside" { return .keyword(kw) }
        return nil
    case .cursor:
        switch kw {
        case "auto", "default", "pointer", "text", "crosshair", "move", "not-allowed", "ew-resize", "ns-resize",
             "col-resize", "row-resize", "wait", "progress", "help", "grab", "grabbing", "none":
            return .keyword(kw)
        default: return nil
        }
    case .visibility:
        switch kw {
        case "visible", "hidden", "collapse": return .keyword(kw)
        default: return nil
        }
    case .borderCollapse:
        if kw == "collapse" || kw == "separate" { return .keyword(kw) }
        return nil
    case .borderSpacing:
        return parseLengthValue(t, allowAuto: false)
    }
}

func isGradientName(_ name: string) -> bool {
    return name == "linear-gradient" || name == "-webkit-linear-gradient" || name == "repeating-linear-gradient" ||
        name == "radial-gradient" || name == "-webkit-radial-gradient"
}

/// The index of the paren closing a function whose arguments start at
/// `from`, or the token count.
func closeParen(_ tokens: [css.Token], from: int) -> int {
    var depth = 1
    var i = from
    while i < tokens.count {
        if tokens[i].Kind == .function || tokens[i].Kind == .openParen { depth += 1 }
        if tokens[i].Kind == .closeParen {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return tokens.count
}

/// A linear-gradient's arguments: an angle or a direction, then color
/// stops with optional positions. A radial gradient is drawn as a
/// linear one from its centre color outward, which is near enough.
func parseGradient(_ tokens: [css.Token], _ start: int, _ end: int) -> draw.LinearGradient? {
    // Split the arguments at top-level commas.
    var args: [[css.Token]] = []
    var current: [css.Token] = []
    var depth = 0
    var i = start
    while i < end {
        let t = tokens[i]
        if t.Kind == .function || t.Kind == .openParen { depth += 1 }
        if t.Kind == .closeParen { depth -= 1 }
        if t.Kind == .comma && depth == 0 {
            args.append(current)
            current = []
        } else {
            current.append(t)
        }
        i += 1
    }
    if !current.isEmpty { args.append(current) }
    if args.isEmpty { return nil }
    var angle: float32 = 180
    var firstStop = 0
    let head = args[0]
    if head.count == 1 && head[0].Kind == .dimension {
        let unit = head[0].Unit
        if unit == "deg" { angle = head[0].NumberVal }
        else if unit == "turn" { angle = head[0].NumberVal * 360 }
        else if unit == "rad" { angle = head[0].NumberVal * 57.29578 }
        else if unit == "grad" { angle = head[0].NumberVal * 0.9 }
        firstStop = 1
    } else if head.count >= 2 && head[0].Kind == .ident && lower(head[0].Value) == "to" {
        var dx: float32 = 0
        var dy: float32 = 0
        var k = 1
        while k < head.count {
            switch lower(head[k].Value) {
            case "left": dx = -1
            case "right": dx = 1
            case "top": dy = -1
            case "bottom": dy = 1
            default: break
            }
            k += 1
        }
        if dx == 0 && dy == 0 { dy = 1 }
        // The angle whose direction is (dx, dy), with 0 pointing up.
        if dx == 0 { angle = dy > 0 ? 180 : 0 }
        else if dy == 0 { angle = dx > 0 ? 90 : 270 }
        else if dx > 0 { angle = dy > 0 ? 135 : 45 }
        else { angle = dy > 0 ? 225 : 315 }
        firstStop = 1
    } else if head.count >= 1 && head[0].Kind == .ident && (lower(head[0].Value) == "circle" || lower(head[0].Value) == "ellipse" || lower(head[0].Value) == "at" || lower(head[0].Value) == "closest-side" || lower(head[0].Value) == "farthest-corner") {
        firstStop = 1
    }
    var stops: [draw.GradientStop] = []
    var positions: [float32] = []
    var k = firstStop
    while k < args.count {
        let arg = args[k]
        if arg.isEmpty { k += 1; continue }
        guard let m = parseColorAt(arg, 0) else { k += 1; continue }
        var color = draw.Color.black
        if case .color(let c) = m.0 { color = c }
        var pos: float32 = -1
        if m.1 < arg.count {
            let pt = arg[m.1]
            if pt.Kind == .percentage { pos = pt.NumberVal / 100 }
            else if pt.Kind == .number { pos = pt.NumberVal }
        }
        stops.append(draw.GradientStop(color, at: pos))
        positions.append(pos)
        k += 1
    }
    if stops.isEmpty { return nil }
    // Missing positions: the first is 0, the last 1, the rest spread
    // evenly between the ones given.
    if stops[0].Position < 0 { stops[0].Position = 0 }
    if stops[stops.count - 1].Position < 0 { stops[stops.count - 1].Position = 1 }
    var i2 = 1
    while i2 < stops.count - 1 {
        if stops[i2].Position < 0 {
            var j = i2 + 1
            while j < stops.count && stops[j].Position < 0 { j += 1 }
            let from = stops[i2 - 1].Position
            let to = stops[j].Position
            let n = float32(j - i2 + 1)
            var m2 = i2
            while m2 < j {
                stops[m2].Position = from + (to - from) * float32(m2 - i2 + 1) / n
                m2 += 1
            }
            i2 = j
        } else {
            i2 += 1
        }
    }
    var i3 = 1
    while i3 < stops.count {
        if stops[i3].Position < stops[i3 - 1].Position { stops[i3].Position = stops[i3 - 1].Position }
        i3 += 1
    }
    return draw.LinearGradient(angle: angle, stops: stops)
}

func parseBackgroundSize(_ tokens: [css.Token]) -> Value? {
    if tokens.isEmpty { return nil }
    if tokens[0].Kind == .ident {
        let kw = lower(tokens[0].Value)
        if kw == "cover" || kw == "contain" || kw == "auto" { return .keyword(kw) }
        return nil
    }
    var words: [string] = []
    for t in tokens {
        if t.Kind == .ident { words.append(lower(t.Value)) }
        else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number { words.append(t.Value) }
    }
    return .keyword(joinWords(words))
}

func parseBackgroundPosition(_ tokens: [css.Token]) -> Value? {
    var words: [string] = []
    for t in tokens {
        if t.Kind == .ident { words.append(lower(t.Value)) }
        else if t.Kind == .percentage || t.Kind == .dimension || t.Kind == .number { words.append(t.Value) }
    }
    if words.isEmpty { return nil }
    return .keyword(joinWords(words))
}
