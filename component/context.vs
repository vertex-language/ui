package component

/// A value given to everything below a point in the tree -- a theme, a
/// store, the signed-in user -- without passing it through each component
/// between.
///
///     let Theme = component.Context<string>("light")
///
///     <Theme.Provider value="dark">
///         <Toolbar />             // and anything Toolbar makes:
///     </Theme.Provider>
///
///     func Button() -> Node {
///         let theme = Theme.Value  // "dark" here, "light" outside any Provider
///         …
///     }
///
/// A component reads it when it runs. What a live part (`{if …}`, a
/// `<For>` row) makes later, when a signal changes, sees the values given
/// where the part was written: Mount runs it inside them. The value is
/// given once; to give a changing one, give a signal, a Readable or a
/// model object, and read through it.
public struct Context<T> {
    let key: int
    let fallback: T

    /// A context, and what reading it outside any Provider gives.
    public init(_ fallback: T) {
        key = newContextKey()
        self.fallback = fallback
    }

    /// Gives value to what children makes.
    public func Provider(value: T, children: Children) -> Node {
        return providing(key, value, children)
    }

    /// The value given by the nearest Provider around the code running
    /// now, or the fallback.
    public var Value: T {
        if let v = provided(key) { return v as! T }
        return fallback
    }
}

/// The values given around the code running now, innermost first.
final class Frame {
    let key: int
    let value: Any
    let next: Frame?

    init(key: int, value: Any, next: Frame?) {
        self.key = key
        self.value = value
        self.next = next
    }
}

var frames: Frame? = nil
var contextKeys = 0

// Context's methods are compiled where they are used, and reach these
// through functions compiled here.

func newContextKey() -> int {
    contextKeys += 1
    return contextKeys
}

func providing(_ key: int, _ value: Any, _ children: Children) -> Node {
    let prev = frames
    frames = Frame(key: key, value: value, next: prev)
    let n = children()
    frames = prev
    return n
}

func provided(_ key: int) -> Any? {
    var f = frames
    while let x = f {
        if x.key == key { return x.value }
        f = x.next
    }
    return nil
}

/// f, run inside the values given where it was made.
func captured(_ f: () -> [Node]) -> () -> [Node] {
    let at = frames
    if at == nil { return f }
    return {
        let prev = frames
        frames = at
        let r = f()
        frames = prev
        return r
    }
}
