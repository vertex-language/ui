# ui/component

What `.vsx` markup lowers to, and what puts it on a page. The compiler
rewrites each element as calls of this package (`proposed_vsx.md` §9.2):

```
<Card title="T">…</Card>          Card(title: "T", children: { component.Fragment([…]) })
<p class="x" onClick={n += 1}>    component.Element("p", [
  Hi {name}                           component.Attribute.Static("class", "x"),
</p>                                  component.Attribute.On("click", dom.MouseEvent.self, { _ in n += 1 }),
                                  ], ["Hi ", name])
<>…</>                            component.Fragment([…])
```

| | |
| :--- | :--- |
| `Node` | An element, text or fragment, described. `Html()` renders it as HTML. |
| `Element`, `Fragment`, `Text` | Make nodes. |
| `Attribute` | `Static`, `Value` (a `Signal<string>` or `Signal<bool>` binds both ways), `On`, `Class`, `Style`, `Ref`, `Spread`. |
| `Renderable` | What a child may be: a node, a string, a number, or an array or optional of them. |
| `Children`, `For` | A component's children; the keyed list. |
| `Mount(root, into:, at:, styles:)` | Puts a root into a `dom.Document` and keeps it there: when a signal the root read changes, it renders again and the document is patched in place, so elements keep their focus and state. `styles` is given the sheets the tree's packages carry, in cascade order, when they change. |
| `Sheet`, `SheetsOf` | A package's compiled `.vss`, which the compiler generates as `__vssSheet` and stamps on the package's elements; the sheets a tree uses, in order. |

This is the check form's runtime: a root renders whole and is patched.
Each component's `@State` keeps its signal between renders by the order it
is made in (`reactive.Slots`), as React's hooks do. The emit form will
bind each hole to its signal and run components once.
