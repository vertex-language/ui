package webview

import "ui/draw"

/// A CSS length as the cascade leaves it: resolved to pixels where the
/// unit allowed, a percentage where only layout can resolve it, or a
/// keyword.
public enum Length: Equatable {
    case auto
    case none
    case px(float32)
    case percent(float32)
    /// calc(): so many pixels plus so much of the base.
    case calc(float32, float32)
    case minContent
    case maxContent
    case fitContent

    public var IsAuto: bool { return self == .auto }
    public var IsNone: bool { return self == .none }

    /// The length in pixels against a base for percentages; nil where it
    /// is a keyword.
    public func Resolve(_ base: float32) -> float32? {
        switch self {
        case .px(let v): return v
        case .percent(let p): return base * p / 100
        case .calc(let v, let p): return v + base * p / 100
        default: return nil
        }
    }

    /// The length in pixels, or a fallback where it is a keyword.
    public func Or(_ fallback: float32, base: float32) -> float32 {
        return Resolve(base) ?? fallback
    }

    /// The length in pixels where it needs no base, or nil.
    public var Pixels: float32? {
        if case .px(let v) = self { return v }
        return nil
    }
}

public enum Display: Equatable {
    case none
    case block
    case inline
    case inlineBlock
    case flex
    case inlineFlex
    case grid
    case inlineGrid
    case listItem
    case table
    case inlineTable
    case tableRow
    case tableCell
    case tableRowGroup
    case tableHeaderGroup
    case tableFooterGroup
    case tableCaption
    case tableColumn
    case tableColumnGroup
    case contents

    /// Whether boxes of this display sit in a line with text.
    public var IsInlineLevel: bool {
        switch self {
        case .inline, .inlineBlock, .inlineFlex, .inlineGrid, .inlineTable: return true
        default: return false
        }
    }

    /// The display a float, an absolutely positioned box or a flex item
    /// takes: the block-level counterpart.
    public var Blockified: Display {
        switch self {
        case .inline, .inlineBlock: return .block
        case .inlineFlex: return .flex
        case .inlineGrid: return .grid
        case .inlineTable: return .table
        default: return self
        }
    }
}

public enum Position: Equatable {
    case `static`
    case relative
    case absolute
    case fixed
    case sticky
}

public enum FloatSide: Equatable {
    case none
    case left
    case right
}

public enum Clear: Equatable {
    case none
    case left
    case right
    case both
}

public enum BoxSizing: Equatable {
    case contentBox
    case borderBox
}

public enum BorderStyle: Equatable {
    case none
    case hidden
    case solid
    case dashed
    case dotted
    case double
    case groove
    case ridge
    case inset
    case outset

    public var Draws: bool { return self != .none && self != .hidden }
}

public enum Overflow: Equatable {
    case visible
    case hidden
    case scroll
    case auto
    case clip

    public var Clips: bool { return self != .visible }
    public var Scrolls: bool { return self == .scroll || self == .auto }
}

public enum TextAlign: Equatable {
    case start
    case end
    case left
    case right
    case center
    case justify
}

public enum WhiteSpace: Equatable {
    case normal
    case nowrap
    case pre
    case preWrap
    case preLine

    public var Collapses: bool { return self == .normal || self == .nowrap || self == .preLine }
    public var Wraps: bool { return self == .normal || self == .preWrap || self == .preLine }
    public var KeepsNewlines: bool { return self == .pre || self == .preWrap || self == .preLine }
}

public enum OverflowWrap: Equatable {
    case normal
    case breakWord
    case anywhere
}

public enum WordBreak: Equatable {
    case normal
    case breakAll
    case keepAll
}

public enum TextOverflow: Equatable {
    case clip
    case ellipsis
}

public enum TextTransform: Equatable {
    case none
    case uppercase
    case lowercase
    case capitalize
}

public enum VerticalAlign: Equatable {
    case baseline
    case middle
    case top
    case bottom
    case textTop
    case textBottom
    case sub
    case `super`
    case length(Length)
}

public enum ListStyleType: Equatable {
    case none
    case disc
    case circle
    case square
    case decimal
    case decimalLeadingZero
    case lowerAlpha
    case upperAlpha
    case lowerRoman
    case upperRoman
}

public enum ListStylePosition: Equatable {
    case outside
    case inside
}

public enum Visibility: Equatable {
    case visible
    case hidden
    case collapse
}

public enum FlexDirection: Equatable {
    case row
    case rowReverse
    case column
    case columnReverse

    public var IsRow: bool { return self == .row || self == .rowReverse }
    public var IsReverse: bool { return self == .rowReverse || self == .columnReverse }
}

public enum FlexWrap: Equatable {
    case nowrap
    case wrap
    case wrapReverse
}

public enum JustifyContent: Equatable {
    case flexStart
    case flexEnd
    case center
    case spaceBetween
    case spaceAround
    case spaceEvenly
}

public enum AlignItems: Equatable {
    case stretch
    case flexStart
    case flexEnd
    case center
    case baseline
    case auto
}

public enum LineHeight: Equatable {
    case normal
    case px(float32)
    case number(float32)
}

public enum FontStyle: Equatable {
    case normal
    case italic
    case oblique
}

public enum CursorKind: Equatable {
    case auto
    case `default`
    case pointer
    case text
    case crosshair
    case move
    case notAllowed
    case ewResize
    case nsResize
    case wait
    case help
    case grab
    case none
}

public enum TableLayout: Equatable {
    case auto
    case fixed
}

public enum BorderCollapse: Equatable {
    case separate
    case collapse
}

/// One track of a grid: a fixed length, a share of the free space, or
/// what its items need.
public enum GridTrack: Equatable {
    case length(Length)
    case fr(float32)
    case auto
    /// minmax(min, max): the minimum in pixels, the maximum in pixels
    /// (0 for none), and the maximum's fr where a share (0 for none).
    case minmax(float32, float32, float32)
}

/// Where a grid item is put: a line, a span, or automatic.
public struct GridPlacement: Equatable {
    /// 1-based start line, 0 for auto.
    public var Start: int32
    /// Lines spanned.
    public var Span: int32

    public init(start: int32 = 0, span: int32 = 1) {
        Start = start
        Span = span
    }

    public static let auto = GridPlacement(start: 0, span: 1)
}

/// Which lines text-decoration draws, as bits.
public struct TextDecoration: Equatable {
    public var Underline: bool = false
    public var Overline: bool = false
    public var LineThrough: bool = false

    public init() {}

    public static let none = TextDecoration()

    public var IsNone: bool { return !Underline && !Overline && !LineThrough }

    public func Union(_ o: TextDecoration) -> TextDecoration {
        var out = self
        if o.Underline { out.Underline = true }
        if o.Overline { out.Overline = true }
        if o.LineThrough { out.LineThrough = true }
        return out
    }
}

public enum BackgroundSize: Equatable {
    case auto
    case cover
    case contain
    case length(Length, Length)
}

/// A background image: a picture by URL, drawn once a loader has
/// answered, or a gradient. How it repeats, where it sits and how big
/// it is come from the other background properties.
public struct BackgroundImage {
    public var URL: string
    public var Gradient: draw.LinearGradient?
    public var RepeatX: bool
    public var RepeatY: bool
    public var Size: BackgroundSize
    /// Position as fractions of the free space: 0 left/top, 0.5 centre, 1 right/bottom.
    public var PositionX: float32
    public var PositionY: float32

    public init(url: string) {
        URL = url
        Gradient = nil
        RepeatX = true
        RepeatY = true
        Size = .auto
        PositionX = 0
        PositionY = 0
    }

    public init(gradient: draw.LinearGradient) {
        URL = ""
        Gradient = gradient
        RepeatX = false
        RepeatY = false
        Size = .auto
        PositionX = 0
        PositionY = 0
    }

    public var IsGradient: bool { return Gradient != nil }
}

/// One shadow of box-shadow.
public struct Shadow: Equatable {
    public var X: float32
    public var Y: float32
    public var Blur: float32
    public var Spread: float32
    public var Color: draw.Color
    public var Inset: bool

    public init(x: float32, y: float32, blur: float32, spread: float32, color: draw.Color, inset: bool) {
        X = x
        Y = y
        Blur = blur
        Spread = spread
        self.Color = color
        Inset = inset
    }
}
