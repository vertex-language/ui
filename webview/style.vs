package webview

import "ui/window"
import "text/html"
import "text/css"
import "text/css/selector"

public enum Display: Equatable {
    case block
    case inline
    case none
}

/// The computed styling values for a DOM node.
public class ComputedStyle {
    public var Display: Display
    public var HasWidth: bool
    public var Width: float32
    public var HasHeight: bool
    public var Height: float32
    public var MarginTop: float32
    public var MarginRight: float32
    public var MarginBottom: float32
    public var MarginLeft: float32
    public var PaddingTop: float32
    public var PaddingRight: float32
    public var PaddingBottom: float32
    public var PaddingLeft: float32
    public var BorderWidth: float32
    public var BorderColor: Color
    public var Color: Color
    public var BackgroundColor: Color
    public var FontSize: float32
    public var LineHeight: float32
    public var Bold: bool
    public var Italic: bool
    public var HasCursor: bool
    public var DesiredCursor: window.Cursor

    public init() {
        self.Display = .inline
        self.HasWidth = false
        self.Width = 0
        self.HasHeight = false
        self.Height = 0
        self.MarginTop = 0
        self.MarginRight = 0
        self.MarginBottom = 0
        self.MarginLeft = 0
        self.PaddingTop = 0
        self.PaddingRight = 0
        self.PaddingBottom = 0
        self.PaddingLeft = 0
        self.BorderWidth = 0
        self.BorderColor = .transparent
        self.Color = .black
        self.BackgroundColor = .transparent
        self.FontSize = 16.0
        self.LineHeight = 20.0
        self.Bold = false
        self.Italic = false
        self.HasCursor = false
        self.DesiredCursor = window.Cursor.arrow
    }
}

/// The Style Engine that matches rules, resolves inheritance, and computes style structs.
public class StyleEngine {
    var uaSheet: css.StyleSheet
    var selectorCache: [string: [selector.ComplexSelector]]

    public init() {
        self.selectorCache = [:]
        let uaCSS = """
        head, style, script, meta, title, link { display: none; }
        html, body { display: block; margin: 8px; color: #1a1a1a; font-size: 16px; }
        h1 { display: block; font-size: 28px; margin-top: 14px; margin-bottom: 14px; font-weight: bold; }
        h2 { display: block; font-size: 22px; margin-top: 12px; margin-bottom: 12px; font-weight: bold; }
        h3 { display: block; font-size: 18px; margin-top: 10px; margin-bottom: 10px; font-weight: bold; }
        p { display: block; margin-top: 10px; margin-bottom: 10px; }
        div, section, article, nav, header, footer, main { display: block; }
        ul, ol { display: block; margin-top: 8px; margin-bottom: 8px; padding-left: 20px; }
        li { display: block; margin-top: 4px; margin-bottom: 4px; }
        a { color: #0969da; }
        hr { display: block; height: 1px; background-color: #d0d7de; margin-top: 16px; margin-bottom: 16px; }
        input { display: inline-block; border: 1px; border-color: #8c959f; padding: 5px 8px; font-size: 14px; background-color: #ffffff; }
        textarea { display: inline-block; border: 1px; border-color: #8c959f; padding: 6px 8px; font-size: 14px; background-color: #ffffff; }
        button { display: inline-block; border: 1px; border-color: #d0d7de; padding: 5px 12px; font-size: 14px; background-color: #f6f8fa; cursor: pointer; }
        """
        self.uaSheet = css.Parse(uaCSS)
    }

    func getCompiledSelectors(_ selectorStr: string) -> [selector.ComplexSelector] {
        if let cached = selectorCache[selectorStr] {
            return cached
        }
        let parsed = selector.ParseSelectors(selectorStr)
        selectorCache[selectorStr] = parsed
        return parsed
    }

    /// Resolves the computed style for a node given author stylesheets and parent style.
    public func Resolve(
        node: html.Node,
        authorSheets: [css.StyleSheet],
        parentStyle: ComputedStyle?
    ) -> ComputedStyle {
        let style = ComputedStyle()

        // 1. Inherit from parent
        if let parent = parentStyle {
            style.Color = parent.Color
            style.FontSize = parent.FontSize
            style.LineHeight = parent.LineHeight
            style.Bold = parent.Bold
            style.Italic = parent.Italic
        }

        if node.Kind != html.NodeKind.element {
            return style
        }

        let tag = toLower(node.TagName)
        if tag == "b" || tag == "strong" || tag == "h1" || tag == "h2" || tag == "h3" || tag == "h4" || tag == "h5" || tag == "h6" {
            style.Bold = true
        } else if tag == "i" || tag == "em" {
            style.Italic = true
        }

        // Cursors for interactive elements
        if tag == "a" || tag == "button" {
            style.DesiredCursor = window.Cursor.pointingHand
            style.HasCursor = true
        } else if tag == "input" || tag == "textarea" {
            style.DesiredCursor = window.Cursor.iBeam
            style.HasCursor = true
        }

        // 2. Apply User-Agent rules
        applyRules(style, uaSheet.Rules, node)

        // 3. Apply Author stylesheets
        var s = 0
        while s < authorSheets.count {
            applyRules(style, authorSheets[s].Rules, node)
            s += 1
        }

        // 4. Apply inline style="..." attributes
        if let inlineStyle = node.GetAttribute("style") {
            let decls = css.ParseDeclarations(inlineStyle)
            var d = 0
            while d < decls.count {
                applyDeclaration(style, decls[d])
                d += 1
            }
        }

        return style
    }

    func applyRules(_ style: ComputedStyle, _ rules: [css.Rule], _ node: html.Node) {
        var r = 0
        while r < rules.count {
            let rule = rules[r]
            var matched = false
            var selIdx = 0
            while selIdx < rule.Selectors.count {
                let complexes = getCompiledSelectors(rule.Selectors[selIdx])
                var c = 0
                while c < complexes.count {
                    if selector.MatchComplex(complexes[c], node) {
                        matched = true
                        break
                    }
                    c += 1
                }
                if matched {
                    break
                }
                selIdx += 1
            }
            if matched {
                var d = 0
                while d < rule.Declarations.count {
                    applyDeclaration(style, rule.Declarations[d])
                    d += 1
                }
            }
            r += 1
        }
    }

    func applyDeclaration(_ style: ComputedStyle, _ decl: css.Declaration) {
        let prop = decl.Property
        let val = decl.Value

        if prop == "display" {
            if val == "block" { style.Display = .block }
            else if val == "inline" { style.Display = .inline }
            else if val == "none" { style.Display = .none }
        } else if prop == "width" {
            style.Width = parseFloat(val)
            style.HasWidth = true
        } else if prop == "height" {
            style.Height = parseFloat(val)
            style.HasHeight = true
        } else if prop == "color" {
            style.Color = Color.Parse(val)
        } else if prop == "background-color" || prop == "background" {
            style.BackgroundColor = Color.Parse(val)
        } else if prop == "font-size" {
            let sz = parseFloat(val)
            if sz > 0 {
                style.FontSize = sz
                style.LineHeight = sz * 1.25
            }
        } else if prop == "line-height" {
            let lh = parseFloat(val)
            if lh > 0 { style.LineHeight = lh }
        } else if prop == "margin" {
            let m = parseFloat(val)
            style.MarginTop = m
            style.MarginRight = m
            style.MarginBottom = m
            style.MarginLeft = m
        } else if prop == "margin-top" {
            style.MarginTop = parseFloat(val)
        } else if prop == "margin-bottom" {
            style.MarginBottom = parseFloat(val)
        } else if prop == "margin-left" {
            style.MarginLeft = parseFloat(val)
        } else if prop == "margin-right" {
            style.MarginRight = parseFloat(val)
        } else if prop == "padding" {
            let p = parseFloat(val)
            style.PaddingTop = p
            style.PaddingRight = p
            style.PaddingBottom = p
            style.PaddingLeft = p
        } else if prop == "padding-top" {
            style.PaddingTop = parseFloat(val)
        } else if prop == "padding-bottom" {
            style.PaddingBottom = parseFloat(val)
        } else if prop == "padding-left" {
            style.PaddingLeft = parseFloat(val)
        } else if prop == "padding-right" {
            style.PaddingRight = parseFloat(val)
        } else if prop == "border" || prop == "border-width" {
            style.BorderWidth = parseFloat(val)
            if style.BorderColor == .transparent {
                style.BorderColor = Color.borderGray
            }
        } else if prop == "border-color" {
            style.BorderColor = Color.Parse(val)
        } else if prop == "font-weight" {
            if val == "bold" || val == "bolder" || val == "700" || val == "800" || val == "900" {
                style.Bold = true
            } else if val == "normal" || val == "400" {
                style.Bold = false
            }
        } else if prop == "font-style" {
            if val == "italic" || val == "oblique" {
                style.Italic = true
            } else if val == "normal" {
                style.Italic = false
            }
        } else if prop == "cursor" {
            style.HasCursor = true
            if val == "pointer" {
                style.DesiredCursor = window.Cursor.pointingHand
            } else if val == "text" {
                style.DesiredCursor = window.Cursor.iBeam
            } else {
                style.DesiredCursor = window.Cursor.arrow
            }
        }
    }
}
