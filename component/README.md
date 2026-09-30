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
| `Attribute` | `Static`, `Value`, `Live` (a `Signal` of a string, Boolean, `int` or `float64` binds both ways; text that does not parse as the number is left), `On`, `Class`/`LiveClass`, `Style`/`LiveStyle`, `Ref`, `Spread`, `Package`. |
| `Renderable` | What a child may be: a node, a string, a number, or an array or optional of them. |
| `Live`, `Component` | A live region (`{expr}`); a component's call, run once. |
| `Children`, `For` | A component's children; the keyed list, `For(each: () -> [T], key:, children: (Readable<T>) -> Node)`. |
| `Context<T>` | A value given to everything below a point: `<Theme.Provider value="dark">…</Theme.Provider>`, read as `Theme.Value`; the fallback outside any Provider. Live parts made later see the values given where they were written. |
| `Ref`, `OnMount`, `Focus` | `@state.State var el: Ref = nil` with `ref={$el}` is the element while it is in the document. `OnMount { }` runs once a component's nodes are in, and `Focus(node)` moves the page's focus. |
| `Mount(root, into:, at:, styles:, focus:)` | Puts a root into a `dom.Document`: the root runs once and its live parts keep themselves up to date. `styles` is given the sheets the nodes' packages carry, in cascade order, when they change. `focus` is how `Focus` moves the page's focus (`web.Page.Focus`). |
| `Sheet`, `SheetsOf` | A package's compiled `.vss`, which the compiler generates as `__vssSheet` and stamps on the package's elements; the sheets a tree uses, in order. |

Mount runs the root once. Each live part -- `{count}`, `class:on={on}`,
`title={x}` -- is its own binding (a `state.Effect`), which updates its
own text or attribute when a signal it read changes. Components run once,
untracked (`Component`), so `@State` in a component is made once. A live
region that holds components makes them again when it changes, and
disposes what the old ones made; `<For>` keeps each key's row, moved where
the key moves, and hands the row its item as a `Readable`.

A value computed in a component's body is computed once: read state inside
braces, or through a closure called there, for it to follow the state.
