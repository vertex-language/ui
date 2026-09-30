# ui/state

The state a `.vsx` app keeps, and what follows it: values that say when
they change, computations that follow them, and effects that run again
when what they read changes (`proposed_vsx.md` §5). It imports nothing --
the rest of `ui` is built on it -- so a model, a cache or anything without
a window can use it too.

```vertex
import "ui/state"

var count = state.Signal(0)
let doubled = state.Computed<int> { count.Value * 2 }
let log = state.Effect { print("count is \(count.Value), doubled \(doubled.Value)") }

count.Value = 1            // the effect runs again
state.Batch {
    count.Value = 2
    count.Value = 3        // ...once, after the batch
}
log.Dispose()
```

| | |
| :--- | :--- |
| `Signal<T>` | A value to read (`Value`, followed) and write. A handle: copies are the same signal; write through a `var`. `Peek()` reads without following. |
| `Computed<T>` | A value computed from others, again only when one changed and it is read. |
| `Effect` | Runs now, and after each change to what it read; `Dispose()` stops it. |
| `Batch { }`, `Untracked { }` | Group writes so effects run once after them; read without following. |
| `@State var x = v` | A signal in a variable: `x` reads and writes it, `$x` is the `Signal`. |
| `Owner`, `WithOwner`, `OnCleanup` | What code made that ends with it. An effect owns what each of its runs makes -- effects, cleanups -- and disposes it before running again. |
| `Readable<T>` | A value to read, live: a signal, or a closure over signals. Members read through it (`todo.Done`). |
| `Slots`, `WithSlots` | Where `@State`s made by code that runs again find themselves, in order. ui/component no longer needs them (its components run once); kept for code that re-runs. |

Effects run synchronously, once per batch, in the order they were told.

```bash
vsc run check-state
```
