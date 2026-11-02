package component

import "ui/state"

/// A class component: `class Clock: Component<ClockProps, ClockState>`,
/// written `<Clock zone="UTC" />`. Its props are set before each render;
/// setState renders it again. The instance is made once and kept while it
/// stays in its place, as a function component's hooks are.
///
///     final class Counter: Component<CounterProps, int> {
///         override init() { super.init(); state = 0 }
///         override func render() -> Node {
///             return <button onClick={setState(state + 1)}>{props.Label} {state}</button>
///         }
///     }
open class Component<P, S> {
    public var props: P! = nil
    public var state: S! = nil
    var fiber: ComponentFiber? = nil
    var shown = false
    var lastState: S! = nil

    public init() {}

    /// Sets the state, and renders the component again.
    public func setState(next: S) {
        state = next
        if let f = fiber { f.schedule() }
    }

    /// What the component is now, from its props and state.
    open func render() -> Node { return Node() }

    /// Called once its nodes are first in the document.
    open func componentDidMount() {}

    /// Called after each render but the first is in the document, with
    /// the props and state of the render before.
    open func componentDidUpdate(prevProps: P, prevState: S) {}

    /// Called as it leaves the document.
    open func componentWillUnmount() {}

    /// The render the compiler lowers `<Comp …/>` to: props given, then
    /// render, inside the instance's fiber.
    public func _mount(props: P, renderFn: () -> Node) -> Node {
        let prevProps = self.props
        let prevState = lastState
        self.props = props
        lastState = state
        fiber = activeFiber()
        let me = self
        useEffect({
            me.componentDidMount()
            onCleanup { me.componentWillUnmount() }
        }, [])
        if shown {
            useEffect({ me.componentDidUpdate(prevProps: prevProps!, prevState: prevState!) })
        } else {
            useEffect({}, [])
        }
        shown = true
        return renderFn()
    }
}

/// state.OnCleanup, for code where `state` is a class component's own.
func onCleanup(f: () -> void) {
    state.OnCleanup(f)
}

/// A class component's call: the instance made where the call was
/// written the first time, kept after that, given its props and rendered.
public func MountClass<C: AnyObject, P>(type: string, inst: C, props: P, mount: @escaping (C, P) -> Node) -> Node {
    return Call(type, {
        let held = useRef<C>(nil)
        if held.current == nil { held.current = inst }
        return mount(held.current!, props)
    })
}

/// A keyed class component's call.
public func MountClass<K, C: AnyObject, P>(key: K, type: string, inst: C, props: P, mount: @escaping (C, P) -> Node) -> Node {
    let n = MountClass(type, inst, props, mount)
    n.key = "\(key)"
    return n
}
