# ui/componenttest

Tests for `.vsx` components, written the way a user meets them: mounted
headless in a real page, found by what they are, clicked and typed into
through the page's own input, and looked at.

```vsx
let screen = componenttest.Mount(width: 420, height: 300) { <App /> }
screen.Type(into: screen.ByPlaceholder("What needs doing?"), "buy milk")
screen.Press("Enter")
check(screen.ByRole("listitem").Count == 1, "adds one item")
screen.Click(screen.ByLabel("done: buy milk"))
check(screen.ByText("buy milk").Style?.Color == draw.Color(150, 150, 150), "done style")
check(screen.Pixels().Matches(golden: "testdata/tasks.png"), "pixels")
```

| | |
| :--- | :--- |
| `Mount(width:height:css:) { root }` | A `Screen`: the root mounted in a page, with its packages' `.vss` styles. |
| `ByRole`, `ByText`, `ByLabel`, `ByPlaceholder`, `ByTestId`, `Query` | What a query finds (`Found`): `Count`, `First`, `Text`, `Value`, `Style`, `Attribute`, `HasClass`. A role is the `role` attribute or the one the tag implies, as an assistive technology reads it. |
| `Click`, `DoubleClick`, `RightClick`, `Hover`, `Type(into:)`, `Replace(in:)`, `Press` | Input through the page's own handling, each in a `state.Batch`. A click moves the pointer there first, as a user's does; `Type` types at the end of what a field holds, `Replace` over it. |
| `await WaitFor { query }` | Lets tasks run -- a `Resource` loading -- until the query finds something, or a timeout passes. |
| `SetDark(_:)` | The page's color scheme. |
| `Pixels()` | `At(x, y)`, `Write(path)`, and `Matches(golden:)`: a golden that does not exist yet is recorded, and later runs are held to it. |

`vsc run check-componenttest` is its own check.
