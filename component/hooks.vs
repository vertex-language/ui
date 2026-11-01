package component

import "ui/state"

// MARK: - Component fibers

/// A function component's instance, `<Counter />` in a document: the
/// hooks its body calls, kept between renders in the order it calls them,
/// and the effects its last render asked for. Mount makes one for each
/// component it puts in a document and keeps it while the component stays
/// where it is in its parent (or keeps its key), giving it its parent's new
/// props by rendering it again.
public final class ComponentFiber {
    /// The component's identity: `kit.Card`.
    let type: string
    var hooks: [Any] = []
    var hookIndex = 0
    /// The component's body, with the props its parent gave last.
    var renderFn: () -> Node
    /// The effects the last render asked for, run once its nodes are in
    /// the document.
    var effects: [() -> void] = []
    /// Moved by a state setter: the mount follows it, and renders again.
    var trigger = state.Signal<int>(0)
    /// What the fiber's mount made: the binding that renders it again.
    let owner = state.Owner()
    /// What the body made as it ran last (an effect, a resource), ended by
    /// the next render.
    let renderOwner = state.Owner()
    /// Whether it is out of the document: its setters render nothing.
    var unmounted = false

    init(_ type: string, _ renderFn: () -> Node) {
        self.type = type
        self.renderFn = renderFn
    }

    /// Runs the body, untracked: a component renders again because its
    /// state was set or its parent rendered, not because of what it read.
    /// What the markup wrote in braces is live by itself.
    func render() -> Node {
        let prev = setActiveFiber(self)
        hookIndex = 0
        effects = []
        renderOwner.Dispose()
        var n: Node = nil
        state.WithOwner(renderOwner) {
            n = state.Untracked { self.renderFn() }
        }
        // Hooks after the last one called this time (the body returned
        // early) are dropped with their cleanups.
        drop(from: hookIndex)
        _ = setActiveFiber(prev)
        return n
    }

    /// Asks for a render after a setter changed a hook's state.
    func schedule() {
        if unmounted { return }
        trigger.Value += 1
    }

    /// The next hook's index.
    func next() -> int {
        let i = hookIndex
        hookIndex += 1
        return i
    }

    /// Drops the hooks from index i on, running their effects' cleanups:
    /// what another component rendered in this place, or the body calling
    /// its hooks in another order, held there.
    func drop(from i: int) {
        if i >= hooks.count { return }
        var kept: [Any] = []
        var k = 0
        while k < hooks.count {
            if k < i {
                kept.append(hooks[k])
            } else if let e = hooks[k] as? EffectSlot {
                e.dispose()
            }
            k += 1
        }
        hooks = kept
    }

    /// Ends the fiber: its render binding, then its effects' cleanups.
    func dispose() {
        unmounted = true
        owner.Dispose()
        renderOwner.Dispose()
        for h in hooks {
            if let e = h as? EffectSlot { e.dispose() }
        }
        effects = []
    }
}

var currentFiber: ComponentFiber? = nil

func activeFiber() -> ComponentFiber? {
    return currentFiber
}

func setActiveFiber(_ f: ComponentFiber?) -> ComponentFiber? {
    let prev = currentFiber
    currentFiber = f
    return prev
}

// MARK: - State

/// A state hook's value, and the fiber its setter renders again.
public final class StateCell<T> {
    public internal(set) var value: T
    let fiber: ComponentFiber?

    init(_ initial: T, _ fiber: ComponentFiber?) {
        self.value = initial
        self.fiber = fiber
    }

    /// Sets the value; one equal to what it holds renders nothing.
    public func set(_ next: T) {
        let same = sameValue(value, next)
        value = next
        if !same, let f = fiber { f.schedule() }
    }

    public func update(_ fn: (T) -> T) {
        set(fn(value))
    }
}

/// What useState gives to change its state: `setCount(3)`, or
/// `setCount { $0 + 1 }` from what it is when the setter runs.
public struct SetState<T> {
    let cell: StateCell<T>

    public init(_ cell: StateCell<T>) {
        self.cell = cell
    }

    public func callAsFunction(_ next: T) {
        cell.set(next)
    }

    public func callAsFunction(_ fn: (T) -> T) {
        cell.update(fn)
    }
}

/// Whether two values are the same, where their type says what that is:
/// the numbers, strings and Booleans, and arrays of them. Any other type
/// is never the same, so setting it always renders.
func sameValue<T>(_ a: T, _ b: T) -> bool {
    if let x = a as? int, let y = b as? int { return x == y }
    if let x = a as? string, let y = b as? string { return x == y }
    if let x = a as? bool, let y = b as? bool { return x == y }
    if let x = a as? float64, let y = b as? float64 { return x == y }
    if let x = a as? float32, let y = b as? float32 { return x == y }
    if let x = a as? int64, let y = b as? int64 { return x == y }
    if let x = a as? [int], let y = b as? [int] { return x == y }
    if let x = a as? [string], let y = b as? [string] { return x == y }
    return false
}

/// A component's state, kept between its renders:
///
///     let (count, setCount) = useState(0)
public func useState<T>(_ initial: T) -> (T, SetState<T>) {
    guard let fiber = activeFiber() else {
        let cell = StateCell<T>(initial, nil)
        return (cell.value, SetState<T>(cell))
    }
    let i = fiber.next()
    if i < fiber.hooks.count, let cell = fiber.hooks[i] as? StateCell<T> {
        return (cell.value, SetState<T>(cell))
    }
    fiber.drop(from: i)
    let cell = StateCell<T>(initial, fiber)
    fiber.hooks.append(cell)
    return (cell.value, SetState<T>(cell))
}

/// useState whose first value is computed, once.
public func useState<T>(_ initial: () -> T) -> (T, SetState<T>) {
    if let fiber = activeFiber(), fiber.hookIndex < fiber.hooks.count, let cell = fiber.hooks[fiber.hookIndex] as? StateCell<T> {
        fiber.hookIndex += 1
        return (cell.value, SetState<T>(cell))
    }
    return useState(initial())
}

/// State changed through a reducer: `dispatch(.increment(by: 5))`.
public func useReducer<S, A>(_ reducer: @escaping (S, A) -> S, _ initial: S) -> (S, (A) -> void) {
    let (value, set) = useState(initial)
    let cell = set.cell
    return (value, { action in cell.set(reducer(cell.value, action)) })
}

public func useReducer<S, A>(_ reducer: @escaping (S, A) -> S, initialState: S) -> (S, (A) -> void) {
    return useReducer(reducer, initialState)
}

// MARK: - Refs

/// A box kept across renders, which setting does not render again: an
/// element given by `ref={…}`, or any value.
///
///     let inputRef = useRef<HTMLElement>(nil)
///     <input ref={inputRef} />
public final class Ref<T> {
    public var current: T?

    public init(_ current: T? = nil) {
        self.current = current
    }
}

public func useRef<T>(_ initial: T? = nil) -> Ref<T> {
    guard let fiber = activeFiber() else { return Ref<T>(initial) }
    let i = fiber.next()
    if i < fiber.hooks.count, let r = fiber.hooks[i] as? Ref<T> { return r }
    fiber.drop(from: i)
    let r = Ref<T>(initial)
    fiber.hooks.append(r)
    return r
}

// MARK: - Effects

/// An effect hook: the dependencies it last ran with, and what its last
/// run left to end -- the cleanup it returned, and what it made (an
/// effect, a task, `state.OnCleanup`) -- ended before it runs again and
/// when the component is gone.
final class EffectSlot {
    var deps: [any Equatable]?
    var cleanup: (() -> void)? = nil
    let owner = state.Owner()

    init(_ deps: [any Equatable]?) {
        self.deps = deps
    }

    func dispose() {
        owner.Dispose()
        if let c = cleanup {
            cleanup = nil
            c()
        }
    }
}

/// Runs effect after the render that called it is in the document, its
/// refs given: on the first render, and on each after it whose deps
/// differ from the last (every render where deps is nil).
///
///     useEffect({ Focus(field) }, [])
public func useEffect(_ effect: @escaping () -> void, _ deps: [any Equatable]? = nil) {
    scheduleEffect(deps, { slot in effect() })
}

/// An effect that returns its cleanup, run before it runs again and when
/// the component is gone (`state.OnCleanup` inside an effect is one too):
///
///     useEffect({
///         let t = startTimer()
///         return { t.Cancel() }
///     }, [])
public func useEffect(_ effect: @escaping () -> (() -> void), _ deps: [any Equatable]? = nil) {
    scheduleEffect(deps, { slot in slot.cleanup = effect() })
}

func scheduleEffect(_ deps: [any Equatable]?, _ run: @escaping (EffectSlot) -> void) {
    guard let fiber = activeFiber() else {
        run(EffectSlot(deps))
        return
    }
    let i = fiber.next()
    var slot: EffectSlot? = nil
    if i < fiber.hooks.count, let s = fiber.hooks[i] as? EffectSlot {
        if let old = s.deps, let now = deps, areDepsEqual(old, now) { return }
        s.deps = deps
        slot = s
    } else {
        fiber.drop(from: i)
        let s = EffectSlot(deps)
        fiber.hooks.append(s)
        slot = s
    }
    let s = slot!
    fiber.effects.append({
        s.dispose()
        state.WithOwner(s.owner) {
            state.Untracked { run(s) }
        }
    })
}

public func useLayoutEffect(_ effect: @escaping () -> void, _ deps: [any Equatable]? = nil) {
    useEffect(effect, deps)
}

public func useInsertionEffect(_ effect: @escaping () -> void, _ deps: [any Equatable]? = nil) {
    useEffect(effect, deps)
}

// MARK: - Memos

final class MemoSlot<T> {
    var value: T
    var deps: [any Equatable]?

    init(_ value: T, _ deps: [any Equatable]?) {
        self.value = value
        self.deps = deps
    }
}

/// compute's value, computed again only when deps differ from the last
/// render's (every render where deps is nil).
public func useMemo<T>(_ compute: () -> T, _ deps: [any Equatable]? = nil) -> T {
    guard let fiber = activeFiber() else { return compute() }
    let i = fiber.next()
    if i < fiber.hooks.count, let slot = fiber.hooks[i] as? MemoSlot<T> {
        if let old = slot.deps, let now = deps, areDepsEqual(old, now) { return slot.value }
        slot.value = compute()
        slot.deps = deps
        return slot.value
    }
    fiber.drop(from: i)
    let slot = MemoSlot<T>(compute(), deps)
    fiber.hooks.append(slot)
    return slot.value
}

public func useCallback<F>(_ callback: F, _ deps: [any Equatable]? = nil) -> F {
    return useMemo({ callback }, deps)
}

var vsxIdCounter = 0

/// An id unique in the program and kept across renders: to tie a
/// `<label htmlFor>` to its field.
public func useId() -> string {
    guard let fiber = activeFiber() else {
        vsxIdCounter += 1
        return ":r\(vsxIdCounter):"
    }
    let i = fiber.next()
    if i < fiber.hooks.count, let id = fiber.hooks[i] as? string { return id }
    fiber.drop(from: i)
    vsxIdCounter += 1
    let id = ":r\(vsxIdCounter):"
    fiber.hooks.append(id)
    return id
}

// Renders are synchronous: a transition is the update itself.

public func useTransition() -> (bool, (@escaping () -> void) -> void) {
    return (false, { scope in scope() })
}

public func startTransition(_ scope: () -> void) {
    scope()
}

public func useDeferredValue<T>(_ value: T) -> T {
    return value
}

func areDepsEqual(_ a: [any Equatable], _ b: [any Equatable]) -> bool {
    if a.count != b.count { return false }
    var i = 0
    while i < a.count {
        if !isEqualAny(a[i], b[i]) { return false }
        i += 1
    }
    return true
}

func isEqualAny(_ a: Any, _ b: Any) -> bool {
    if let x = a as? int, let y = b as? int { return x == y }
    if let x = a as? string, let y = b as? string { return x == y }
    if let x = a as? bool, let y = b as? bool { return x == y }
    if let x = a as? float64, let y = b as? float64 { return x == y }
    if let x = a as? float32, let y = b as? float32 { return x == y }
    if let x = a as? int64, let y = b as? int64 { return x == y }
    return false
}
