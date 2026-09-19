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
        case .inline, .inlineBlock, .inlineFlex, .inlineTable: return true
        default: return false
        }
    }

    /// The display a float, an absolutely positioned box or a flex item
    /// takes: the block-level counterpart.
    public var Blockified: Display {
        switch self {
        case .inline, .inlineBlock: return .block
        case .inlineFlex: return .flex
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

public enum Cursor: Equatable {
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

/// A background image, when the page sets one: kept by URL and drawn
/// where a loader has answered.
public struct BackgroundImage: Equatable {
    public var URL: string
    public var Repeat: bool
    public var Cover: bool

    public init(url: string, repeats: bool = true, cover: bool = false) {
        URL = url
        Repeat = repeats
        Cover = cover
    }
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
