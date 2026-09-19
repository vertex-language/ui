package webview

import "text/html"
import "ui/draw"
import "ui/font"

/// What kind of box a layout box is.
public enum BoxKind: Equatable {
    /// A block-level container: its children are blocks, or lines.
    case block
    /// An inline element's box: its children flow in its parent's lines.
    case inline
    /// A run of text, which inline layout splits into fragments.
    case text
    /// An inline-level box laid out as a block inside: inline-block,
    /// inline-flex, inline-table.
    case inlineBlock
    /// An image or a form control: a box with a size of its own.
    case replaced
    /// A <br>.
    case lineBreak
}

/// What a replaced box shows.
public enum ReplacedKind: Equatable {
    case none
    case image
    case textInput
    case textArea
    case button
    case checkbox
    case radio
    case select
    case progress
    case placeholder
}

/// A box in the layout tree: an element, a run of text, or an anonymous
/// wrapper layout needs. Positions are in CSS pixels relative to the
/// parent box's border-box corner; sizes are border-box sizes.
var nextBoxId: int = 1

public final class Box {
    /// A number of its own, for telling boxes apart.
    public let Id: int
    public weak var Node: html.Node?
    public var Kind: BoxKind
    public var Style: ComputedStyle
    public var Children: [Box] = []
    public weak var Parent: Box?
    /// A box layout made with no element of its own: a block wrapping
    /// inline content beside blocks, or a list marker.
    public var IsAnonymous: bool = false

    public var X: float32 = 0
    public var Y: float32 = 0
    public var Width: float32 = 0
    public var Height: float32 = 0
    public var Margin: draw.Edges = draw.Edges.zero
    public var Border: draw.Edges = draw.Edges.zero
    public var Padding: draw.Edges = draw.Edges.zero

    /// The lines of a block container holding inline content.
    public var Lines: [Line] = []
    /// The text of a text box, whitespace as the source has it.
    public var Text: string = ""
    public var Replaced: ReplacedKind = .none
    /// The marker text of a list item: "•", "3.", "iv.".
    public var Marker: string = ""
    /// A replaced box's own size, before CSS: an image's pixels, a
    /// control's default.
    public var IntrinsicWidth: float32 = 0
    public var IntrinsicHeight: float32 = 0
    /// The image a replaced image box shows, once loaded.
    public var Image: draw.Image? = nil
    /// The baseline of the box's first line, from its top, for aligning
    /// it in a line of its parent's; nil where it has no line.
    public var Baseline: float32? = nil
    /// How far the box's content reaches past its padding box, for
    /// scrolling: the far edges of what it holds.
    public var ContentWidth: float32 = 0
    public var ContentHeight: float32 = 0
    /// Where a scroll container is scrolled to.
    public var ScrollX: float32 = 0
    public var ScrollY: float32 = 0
    /// The offset position: relative gives, sticky gives, the rest is 0.
    public var OffsetX: float32 = 0
    public var OffsetY: float32 = 0
    /// Boxes positioned absolutely against this one, laid out after it.
    public var Positioned: [Box] = []
    /// The content height known before the content is laid out, when
    /// the height is given: what children's percentages measure against.
    public var DefiniteInnerHeight: float32? = nil

    public init(kind: BoxKind, style: ComputedStyle, node: html.Node?) {
        Id = nextBoxId
        nextBoxId += 1
        Kind = kind
        Style = style
        Node = node
    }

    public var IsBlockLevel: bool { return Kind == .block }
    public var IsInlineLevel: bool { return Kind != .block }
    public var IsReplaced: bool { return Kind == .replaced }
    public var IsAtomicInline: bool { return Kind == .inlineBlock || Kind == .replaced }

    /// The content box, relative to the border-box corner.
    public var ContentX: float32 { return Border.Left + Padding.Left }
    public var ContentY: float32 { return Border.Top + Padding.Top }
    public var InnerWidth: float32 { return Width - Border.Horizontal - Padding.Horizontal }
    public var InnerHeight: float32 { return Height - Border.Vertical - Padding.Vertical }
    public var PaddingBoxX: float32 { return Border.Left }
    public var PaddingBoxY: float32 { return Border.Top }
    public var PaddingBoxWidth: float32 { return Width - Border.Horizontal }
    public var PaddingBoxHeight: float32 { return Height - Border.Vertical }

    /// The border box as a rect at the box's position.
    public var Rect: draw.Rect { return draw.Rect(X, Y, Width, Height) }
    /// The margin box's height: what the box takes up in a block flow.
    public var OuterHeight: float32 { return Height + Margin.Vertical }
    public var OuterWidth: float32 { return Width + Margin.Horizontal }

    /// Whether the box establishes a new block formatting context: its
    /// margins do not collapse through it and floats stay inside.
    public var IsFormattingRoot: bool {
        if Kind != .block { return true }
        if Style.IsOutOfFlow || Style.ClipsOverflow || Style.IsFlexContainer { return true }
        if Style.Display == .table || Style.Display == .tableCell || Style.Display == .inlineBlock { return true }
        return false
    }

    /// Whether the children flow as lines rather than blocks.
    public var HasInlineChildren: bool {
        if Children.isEmpty { return false }
        return Children[0].IsInlineLevel
    }

    public func AppendChild(_ child: Box) {
        child.Parent = self
        Children.append(child)
    }

    /// The nearest ancestor that is an element's box, for text and
    /// anonymous boxes.
    public var ElementBox: Box? {
        var cur: Box? = self
        while let b = cur {
            if !b.IsAnonymous && b.Kind != .text && b.Node != nil { return b }
            cur = b.Parent
        }
        return nil
    }

    /// The element node the box or its nearest non-anonymous ancestor
    /// belongs to.
    public var Element: html.Node? {
        return ElementBox?.Node
    }
}

/// One line of a block container's inline content.
public struct Line {
    /// The line box, relative to the container's border-box corner.
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// The baseline, from the line's top.
    public var Baseline: float32
    /// Text and atomic boxes on the line, in order.
    public var Fragments: [Fragment]
    /// The stretch of each inline element on the line, for its
    /// background and border, in tree order: outer before inner.
    public var Spans: [Span]

    public init(x: float32, y: float32, width: float32) {
        X = x
        Y = y
        Width = width
        Height = 0
        Baseline = 0
        Fragments = []
        Spans = []
    }
}

public enum FragmentKind: Equatable {
    case text
    case atomic
    case marker
}

/// A piece of a line: a run of text in one style, or an atomic box.
public struct Fragment {
    public var Kind: FragmentKind
    /// The text box, or the atomic box.
    public var Box: Box
    /// The nearest element box, whose style the text is set in.
    public var Owner: Box
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// The baseline from the fragment's top.
    public var Ascent: float32
    public var Text: string
    public var Run: font.Run
    /// Where the fragment's text starts in the box's text, in bytes,
    /// for editing and hit testing.
    public var Offset: int
    public var Decoration: TextDecoration
    public var DecorationColor: draw.Color

    public init(kind: FragmentKind, box: Box, owner: Box) {
        Kind = kind
        Box = box
        Owner = owner
        X = 0
        Y = 0
        Width = 0
        Height = 0
        Ascent = 0
        Text = ""
        Run = font.Run()
        Offset = 0
        Decoration = TextDecoration()
        DecorationColor = draw.Color.black
    }
}

/// The stretch of an inline element's box along one line.
public struct Span {
    public var Box: Box
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    /// Whether this is the element's first or last line, which is where
    /// its left and right padding, border and margin go.
    public var IsFirst: bool
    public var IsLast: bool
}
