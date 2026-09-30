# ui/app

`app.Run` runs a `.vsx` program as a desktop app: a window, a page in it
drawn by the web engine, and a root of markup mounted into the page.

```vsx
func main() async -> int32 {
    return await app.Run(title: "Counter", width: 360, height: 200) { <Counter start={5} /> }
}
```

Styles come from the program's and its packages' `.vss` files: the page is
given each package's sheet, in cascade order, as its elements appear.
`css:` adds a string of CSS under them, for a quick experiment.

Events reach the page's elements as DOM events; the handlers they run
write state; the root renders again once the event is done, and the frame
after shows it. `--snapshot out.png` on the command line draws the first
frame into a PNG and quits.

This is the first form: one window. The markup form of the RFC (`<app.Window>`, menus, status
items) comes after.
