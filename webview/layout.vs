package webview

import "text/html"

public enum BoxKind: Equatable {
    case block
    case inline
    case text
}

public enum ControlKind: Equatable {
    case none
    case input
    case textarea
    case button
}

/// A laid-out rectangular box with styling, dimensions, and DOM association.
public class LayoutBox {
    public weak var Node: html.Node?
    public var Kind: BoxKind
    public var Control: ControlKind
    public var Value: string
    public var Placeholder: string
    public var Style: ComputedStyle
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32
    public var Text: string
    public var Children: [LayoutBox]

    public init(kind: BoxKind, style: ComputedStyle = ComputedStyle()) {
        self.Node = nil
        self.Kind = kind
        self.Control = .none
        self.Value = ""
        self.Placeholder = ""
        self.Style = style
        self.X = 0
        self.Y = 0
        self.Width = 0
        self.Height = 0
        self.Text = ""
        self.Children = []
    }

    /// The outer border box rectangle including padding and borders.
    public func BorderRect() -> (x: float32, y: float32, width: float32, height: float32) {
        let bx = X - Style.PaddingLeft - Style.BorderWidth
        let by = Y - Style.PaddingTop - Style.BorderWidth
        let bw = Width + Style.PaddingLeft + Style.PaddingRight + Style.BorderWidth * 2.0
        let bh = Height + Style.PaddingTop + Style.PaddingBottom + Style.BorderWidth * 2.0
        return (x: bx, y: by, width: bw, height: bh)
    }

    /// Checks if a point (px, py) falls inside this box's border area.
    public func HitTest(px: float32, py: float32) -> LayoutBox? {
        let b = BorderRect()
        if px >= b.x && px <= b.x + b.width && py >= b.y && py <= b.y + b.height {
            if self.Control == .button || self.Control == .input || self.Control == .textarea {
                return self
            }
            // Check children first (top-most / deepest child gets hit)
            var i = Children.count - 1
            while i >= 0 {
                if let hit = Children[i].HitTest(px: px, py: py) {
                    return hit
                }
                i -= 1
            }
            return self
        }
        return nil
    }
}

/// Computes the layout tree and coordinates for a DOM document.
public class LayoutEngine {
    var styleEngine: StyleEngine

    public init(styleEngine: StyleEngine) {
        self.styleEngine = styleEngine
    }

    /// Builds the layout tree for the given DOM node within available viewport width.
    public func BuildLayout(
        root: html.Node,
        authorSheets: [css.StyleSheet],
        viewportWidth: float32
    ) -> (rootBox: LayoutBox, totalHeight: float32) {
        let rootStyle = styleEngine.Resolve(node: root, authorSheets: authorSheets, parentStyle: nil)
        let rootBox = LayoutBox(kind: BoxKind.block, style: rootStyle)
        rootBox.Node = root
        rootBox.X = 0
        rootBox.Y = 0
        rootBox.Width = viewportWidth

        let totalH = layoutChildren(parentBox: rootBox, node: root, authorSheets: authorSheets, availableWidth: viewportWidth)
        rootBox.Height = totalH
        return (rootBox: rootBox, totalHeight: totalH)
    }

    func layoutChildren(
        parentBox: LayoutBox,
        node: html.Node,
        authorSheets: [css.StyleSheet],
        availableWidth: float32
    ) -> float32 {
        let lineStartX = parentBox.X + parentBox.Style.PaddingLeft + parentBox.Style.BorderWidth
        var curX: float32 = lineStartX
        var curY: float32 = parentBox.Y + parentBox.Style.PaddingTop + parentBox.Style.BorderWidth
        var currentLineHeight: float32 = 0

        var i = 0
        while i < node.Children.count {
            let child = node.Children[i]

            if child.Kind == html.NodeKind.text {
                if parentBox.Style.Display == .none {
                    i += 1
                    continue
                }
                let textStr = collapseWhitespace(child.Text, preserveLeading: curX > lineStartX)
                if !textStr.isEmpty {
                    let isBold = parentBox.Style.Bold
                    let isItalic = parentBox.Style.Italic
                    let measure = FontRenderer.MeasureText(textStr, fontSize: parentBox.Style.FontSize, bold: isBold, italic: isItalic)
                    let textW = measure.width
                    let textH = measure.height

                    // Word wrap check
                    if curX > lineStartX && curX + textW > parentBox.X + availableWidth {
                        curX = lineStartX
                        curY += currentLineHeight > 0 ? currentLineHeight : textH
                        currentLineHeight = textH
                    } else {
                        if textH > currentLineHeight { currentLineHeight = textH }
                    }

                    let textBox = LayoutBox(kind: BoxKind.text, style: parentBox.Style)
                    textBox.Node = child
                    textBox.Text = textStr
                    textBox.X = curX
                    textBox.Y = curY
                    textBox.Width = textW
                    textBox.Height = textH
                    parentBox.Children.append(textBox)

                    curX += textW
                }
            } else if child.Kind == html.NodeKind.element {
                let childStyle = styleEngine.Resolve(node: child, authorSheets: authorSheets, parentStyle: parentBox.Style)
                if childStyle.Display == .none {
                    i += 1
                    continue
                }

                let tag = toLower(child.TagName)
                if tag == "input" {
                    let ctrlBox = LayoutBox(kind: BoxKind.inline, style: childStyle)
                    ctrlBox.Node = child
                    ctrlBox.Control = .input
                    ctrlBox.Value = getNodeValue(child)
                    ctrlBox.Placeholder = getNodePlaceholder(child)
                    ctrlBox.X = curX
                    ctrlBox.Y = curY
                    let w = childStyle.HasWidth ? childStyle.Width : 200.0
                    let h = childStyle.HasHeight ? childStyle.Height : 28.0
                    ctrlBox.Width = w
                    ctrlBox.Height = h
                    parentBox.Children.append(ctrlBox)
                    curX += w + 8.0
                    if h > currentLineHeight { currentLineHeight = h }
                } else if tag == "textarea" {
                    if currentLineHeight > 0 {
                        curY += currentLineHeight
                        currentLineHeight = 0
                        curX = lineStartX
                    }
                    curY += childStyle.MarginTop

                    let ctrlBox = LayoutBox(kind: BoxKind.block, style: childStyle)
                    ctrlBox.Node = child
                    ctrlBox.Control = .textarea
                    ctrlBox.Value = getNodeValue(child)
                    ctrlBox.Placeholder = getNodePlaceholder(child)
                    ctrlBox.X = parentBox.X + parentBox.Style.PaddingLeft + childStyle.MarginLeft
                    ctrlBox.Y = curY
                    let w = childStyle.HasWidth ? childStyle.Width : (availableWidth > 320.0 ? 320.0 : availableWidth)
                    let h = childStyle.HasHeight ? childStyle.Height : 80.0
                    ctrlBox.Width = w
                    ctrlBox.Height = h
                    parentBox.Children.append(ctrlBox)
                    curY = ctrlBox.Y + ctrlBox.Height + childStyle.MarginBottom
                } else if tag == "button" {
                    let ctrlBox = LayoutBox(kind: BoxKind.inline, style: childStyle)
                    ctrlBox.Node = child
                    ctrlBox.Control = .button
                    ctrlBox.X = curX
                    ctrlBox.Y = curY
                    let childH = layoutChildren(parentBox: ctrlBox, node: child, authorSheets: authorSheets, availableWidth: availableWidth - (curX - parentBox.X))
                    var contentW: float32 = 0
                    if ctrlBox.Children.count > 0 {
                        let lastChild = ctrlBox.Children[ctrlBox.Children.count - 1]
                        contentW = (lastChild.X + lastChild.Width) - curX
                    }
                    let w = childStyle.HasWidth ? childStyle.Width : (contentW + 20.0)
                    let h = childStyle.HasHeight ? childStyle.Height : (childH > 28.0 ? childH : 28.0)
                    ctrlBox.Width = w
                    ctrlBox.Height = h
                    parentBox.Children.append(ctrlBox)
                    curX += w + 8.0
                    if h > currentLineHeight { currentLineHeight = h }
                } else if childStyle.Display == .block {
                    // Flush inline line before block
                    if currentLineHeight > 0 {
                        curY += currentLineHeight
                        currentLineHeight = 0
                        curX = lineStartX
                    }

                    curY += childStyle.MarginTop

                    let blockBox = LayoutBox(kind: BoxKind.block, style: childStyle)
                    blockBox.Node = child
                    blockBox.X = parentBox.X + parentBox.Style.PaddingLeft + childStyle.MarginLeft
                    blockBox.Y = curY
                    let contentWidth = childStyle.HasWidth ? childStyle.Width : (availableWidth - childStyle.MarginLeft - childStyle.MarginRight - parentBox.Style.PaddingLeft - parentBox.Style.PaddingRight)
                    blockBox.Width = contentWidth > 0 ? contentWidth : 0

                    let childH = layoutChildren(parentBox: blockBox, node: child, authorSheets: authorSheets, availableWidth: blockBox.Width)
                    blockBox.Height = childStyle.HasHeight ? childStyle.Height : childH

                    curY = blockBox.Y + blockBox.Height + childStyle.MarginBottom
                    parentBox.Children.append(blockBox)
                } else {
                    // Inline element (e.g. <span>, <a>)
                    let inlineBox = LayoutBox(kind: BoxKind.inline, style: childStyle)
                    inlineBox.Node = child
                    inlineBox.X = curX
                    inlineBox.Y = curY

                    let childH = layoutChildren(parentBox: inlineBox, node: child, authorSheets: authorSheets, availableWidth: availableWidth - (curX - parentBox.X))

                    if inlineBox.Children.count > 0 {
                        let lastChild = inlineBox.Children[inlineBox.Children.count - 1]
                        inlineBox.Width = (lastChild.X + lastChild.Width) - curX
                    } else {
                        inlineBox.Width = 0
                    }
                    inlineBox.Height = childH > childStyle.LineHeight ? childH : childStyle.LineHeight
                    parentBox.Children.append(inlineBox)

                    curX += inlineBox.Width
                    if inlineBox.Height > currentLineHeight {
                        currentLineHeight = inlineBox.Height
                    }
                }
            }

            i += 1
        }

        if currentLineHeight > 0 {
            curY += currentLineHeight
        }
        curY += parentBox.Style.PaddingBottom + parentBox.Style.BorderWidth
        return curY - parentBox.Y
    }
}
