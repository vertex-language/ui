// Package icon shows an icon from the icons repository in a page: its
// <svg>, at a size, in the text's color wherever the set draws in
// currentColor.
//
//     import (
//         "icons/lucide"
//         "ui/icon"
//     )
//
//     <button><icon.Icon of={lucide.Settings} size={16} /> Settings</button>
package icon

import (
    "icons"
    "ui/component"
)

/// The icon's <svg>, size CSS pixels square, with the class "icon".
public func Icon(of: icons.Icon, size: float32 = 16) -> component.Node {
    let root = of.Root
    let px = size == float32(int(size)) ? "\(int(size))" : "\(size)"
    var attrs: [component.Attribute] = [
        component.Attribute.Static("class", "icon"),
        component.Attribute.Static("width", px),
        component.Attribute.Static("height", px),
    ]
    for (k, v) in root.Attributes where k != "width" && k != "height" {
        attrs.append(component.Attribute.Static(k, v))
    }
    return component.Element("svg", attrs, root.Children.map { node($0) })
}

/// An element of the drawing, and what is inside it.
func node(_ e: icons.Element) -> component.Node {
    var attrs: [component.Attribute] = []
    for (k, v) in e.Attributes { attrs.append(component.Attribute.Static(k, v)) }
    return component.Element(e.Tag, attrs, e.Children.map { node($0) })
}
