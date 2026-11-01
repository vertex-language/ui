# ui/component

What `.vsx` markup lowers to, and what puts it on a page. The compiler
rewrites each element as calls of this package (`docs/vsx.md` in vsc):

```
<Card title="T">…</Card>            component.Component { Card(title: "T", children: { component.Fragment([…]) }) }
<Row key={id} />                    component.Key(id) { Row() }
<p className="x" onClick={setN(n + 1)}> component.Element("p", [
  Hi {name}                             component.Attribute.Static("class", "x"),
</p>                                    component.Attribute.On("click", dom.MouseEvent.self, { _ in setN(n + 1) }),
                                    ], ["Hi ", component.Live { name }])
<>…</>                              component.Fragment([…])
```

| | |
| :--- | :--- |
| `Node`, `Element` | An element, text, fragment or component, described. `Html()` / `renderToString(_)` renders it as HTML. |
| `Element`, `Fragment`, `Text` | Make nodes. |
| `Attribute` | `Static`, `Value`, `Live`, `On`, `Key`, `Ref`, `Spread`, `Package`. A field is controlled: `value={draft} onInput={e in setDraft(e.Value)}`. |
| `Style`, `CSSValue` | Typed inline CSS declarations (`style={Style(color: "red", padding: 12)}`). |
| `Renderable` | What a child may be: a node, a string, a number, or an array or optional of them. |
| `Component`, `Key`, `Live` | A component's call, rendered by a fiber; a keyed one (`<Row key={id} />`), whose fiber goes with its key; a live part (`{expr}`). |
| `useState`, `useReducer` | A component's state: `let (count, setCount) = useState(0)`; `setCount(1)` or `setCount { $0 + 1 }` renders it again (a value equal to the one held renders nothing). |
| `useEffect`, `useLayoutEffect` | Runs after the render is in the document and its refs given, again when its deps change. `state.OnCleanup` inside it is its cleanup: run before it runs again, and when the component goes. |
| `useRef`, `Ref<T>` | A box kept across renders; `ref={el}` holds the element while it is in the document. `ref={setEl}` gives it to a setter. |
| `useMemo`, `useCallback`, `useId`, `useTransition`, `useDeferredValue` | As in React. Renders are synchronous, so a transition is its update. |
| `Focus`, `Bounds` | Move the page's focus to an element or a ref's; where one is laid out. |
| `Children` | A component's children closure (`() -> Node`). |
| `Context<T>`, `createContext`, `use` | A value given to everything below a point: `<Theme value="dark">…</Theme>`, read via `use(Theme)`; the fallback outside any provider. Live parts made later see the values given where they were written. |
| `Mount(root, into:, at:, styles:, focus:, measure:)` | Puts a root into a `dom.Document` and keeps it reconciled. `styles` is given the sheets the nodes' packages carry, in cascade order, when they change; `focus` and `measure` are how `Focus` and `Bounds` reach the page. |
| `Sheet`, `Token`, `Styled` | A package's compiled `.vss`, which the compiler generates as `__vssSheet` and stamps on the package's elements; its `@property` tokens; content carrying a sheet. |

Mount keeps what each node became, and applies the next description of
the same place to it: an element keeps its element (its identity, its
focus) and has its attributes, handlers and children patched; a component
keeps its fiber -- its hooks -- and renders the props its parent gives it
now; siblings are matched by `key` where they have one, by place where
they don't, and only to a node of the same kind and tag. A component
renders again when its state is set or its parent renders; its body runs
untracked.

What markup writes in braces -- `{count}`, `className={on ? "on" : ""}`,
`{items.map { … }}` -- is live besides: its own binding (a `state.Effect`),
which follows the signals it read, such as an `@Observable` model's
properties, and updates its text, attribute or region without its
component rendering again.
