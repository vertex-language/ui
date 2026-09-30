# ui/kit

A few styled components (`Card`, `Button`): the example of a library
with styles of its own. `kit.vss` reaches the kit's own elements and stops
at the program's.

Its tokens are its styling API, registered with `@property` in `kit.vss`
and generated as `kit.Tokens`:

| Token | Syntax | Default |
| :--- | :--- | :--- |
| `--kit-accent` (`kit.Tokens.Accent`) | `<color>` | `rgb(0, 0, 255)` |
| `--kit-radius` (`kit.Tokens.Radius`) | `<length>` | `6px` |

A program themes the kit by setting them: on `:root` in its own `.vss`
(`:root { --kit-accent: black }`), or on an element in markup
(`<div style:--kit-accent="green">`). vsc checks each name against these.
