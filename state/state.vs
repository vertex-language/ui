// Package state is the signal graph: values that say when they change,
// computations that follow them, and effects that run again when what
// they read does -- the state a .vsx component keeps (`@state.State`),
// and what follows it (proposed_vsx.md §5). It imports nothing: the rest
// of ui is built on it, not the other way round, so a model, a cache or a
// scene can use it without windows.
//
// Reading a Signal or a Computed inside a running Effect or Computed
// records the read. Writing a Signal tells what read it; an Effect that
// is told runs again, once, after the writes around it are done: at once
// outside a Batch, and when the outermost Batch ends inside one.
package state

// The graph's classes dispatch nothing through a class table: a generic
// subclass specialized in another module does not have this module's
// internal methods in its table, so every method here is final, and an
// observer that is told does what its kind does.

/// Something that is read: it keeps what read it, to tell them.
public class Source {
    var observers: [Observer] = []

    init() {}

    final func track() {
        if let o = observing() {
            o.depend(on: self)
        }
    }

    final func changed() {
        // A copy: telling an observer may change who observes.
        let told = observers
        for o in told { o.invalidate() }
    }

    final func remove(_ o: Observer) {
        var kept: [Observer] = []
        for x in observers where x !== o { kept.append(x) }
        observers = kept
    }
}

/// Something that reads: it keeps what it read, to stop following them.
public class Observer: Source {
    var sources: [Source] = []
    /// For a computed value: whether what it read has changed since.
    var dirty = true

    override init() {}

    final func depend(on s: Source) {
        for x in sources where x === s { return }
        sources.append(s)
        s.observers.append(self)
    }

    final func clearSources() {
        for s in sources { s.remove(self) }
        sources = []
    }

    /// Something this read has changed: an effect is scheduled to run
    /// again, and a computed value is marked and tells its own readers.
    final func invalidate() {
        if let e = self as? Effect {
            e.schedule()
            return
        }
        if dirty { return }
        dirty = true
        self.changed()
    }
}

/// The observer whose reads are being recorded, or nil.
var current: Observer? = nil
/// How deep inside Batch the writes are.
var batchDepth = 0
/// The effects told of a change and waiting to run.
var pending: [Effect] = []
var flushing = false

// Generic code is specialized in the module that uses it, which cannot
// reach this one's variables; it goes through these functions instead,
// compiled here.

func observing() -> Observer? { return current }

func observe(_ o: Observer?) -> Observer? {
    let prev = current
    current = o
    return prev
}

func written() {
    if batchDepth == 0 { flush() }
}



func flush() {
    if flushing { return }
    flushing = true
    while !pending.isEmpty {
        let e = pending.removeFirst()
        e.scheduled = false
        e.execute()
    }
    flushing = false
}

// The graph itself is non-generic classes, compiled here; the generic
// types are handles on them, so nothing generic is a class. (vsc does not
// yet specialize a generic class's accessors across modules, and has no
// nonmutating setter for a property: a handle is written through a var.)

/// A signal's storage. Public because a signal's accessors are compiled
/// where they are used; use Signal.
public final class Cell: Source {
    var value: Any

    init(_ value: Any) {
        self.value = value
    }

    func read() -> Any {
        self.track()
        return value
    }

    func write(_ v: Any) {
        value = v
        self.changed()
        written()
    }
}

/// A computed value's storage: the computation, what it last gave, and
/// whether that is stale. Public for the same reason as Cell; use Computed.
public final class Derived: Observer {
    let compute: () -> Any
    var cached: Any? = nil

    init(_ compute: () -> Any) {
        self.compute = compute
    }

    func read() -> Any {
        self.track()
        if dirty || cached == nil {
            self.clearSources()
            let prev = observe(self)
            cached = compute()
            _ = observe(prev)
            dirty = false
        }
        return cached!
    }
}

/// A value that can be read and written; reading it inside an effect or
/// a computation makes that one follow it. A handle: copies of a signal
/// are the same signal, and writing through any `var` of it writes it.
public struct Signal<T> {
    let cell: Cell

    public init(_ value: T) {
        cell = Cell(value)
    }

    init(cell: Cell) {
        self.cell = cell
    }

    public var Value: T {
        get { return cell.read() as! T }
        set { cell.write(newValue) }
    }

    /// The value, without following it.
    public func Peek() -> T { return cell.value as! T }
}

/// A value computed from others, again only when one of them has changed
/// and it is read.
public struct Computed<T> {
    let derived: Derived

    public init(_ compute: () -> T) {
        derived = Derived({ compute() })
    }

    public var Value: T { return derived.read() as! T }
}

/// A reaction: runs now, and again after each change to what it read the
/// last time it ran, until it is disposed. For talking to the world
/// outside the graph -- a document, a file, a socket -- not for values,
/// which Computed is for.
public final class Effect: Observer {
    let run: () -> void
    var scheduled = false
    public internal(set) var Disposed = false
    /// What the effect's last run made: effects and cleanups, disposed
    /// before it runs again and when it is disposed.
    let owned = Owner()

    public init(_ run: () -> void) {
        self.run = run
        super.init()
        adopt(self)
        execute()
    }

    final func schedule() {
        if scheduled || Disposed { return }
        scheduled = true
        pending.append(self)
    }

    final func execute() {
        if Disposed { return }
        self.clearSources()
        owned.Dispose()
        let prevOwner = own(owned)
        let prev = observe(self)
        run()
        _ = observe(prev)
        _ = own(prevOwner)
    }


    /// Stops following: the effect never runs again, and what it made is
    /// disposed.
    public func Dispose() {
        Disposed = true
        self.clearSources()
        owned.Dispose()
    }
}

/// Runs body, and runs the effects its writes tell once, after it.
public func Batch(_ body: () -> void) {
    batchDepth += 1
    body()
    batchDepth -= 1
    if batchDepth == 0 { flush() }
}

/// Reads inside body without following what is read.
public func Untracked<T>(_ body: () -> T) -> T {
    let prev = observe(nil)
    let v = body()
    _ = observe(prev)
    return v
}

/// A signal kept in a variable: `@State var count = 0` reads and writes
/// the signal's value as `count`, and `$count` is the signal itself.
@propertyWrapper
public struct State<T> {
    var signal: Signal<T>

    public init(wrappedValue: T) {
        // Rendered again inside the same slots, the state is the one it
        // was the first time: see Slots.
        if let cell = claimSlot() {
            signal = Signal<T>(cell: cell)
        } else {
            signal = Signal<T>(wrappedValue)
            fillSlot(signal.cell)
        }
    }

    public var wrappedValue: T {
        get { return signal.Value }
        set { signal.Value = newValue }
    }

    public var projectedValue: Signal<T> { return signal }
}



/// The state of code that runs more than once and should find its state
/// where it left it: a component rendered again by ui/component's check
/// form. Inside WithSlots, each State made takes the next slot in order,
/// and on the next run in the same slots gets the signal it had -- which
/// holds as long as the states are made in the same order each time, as
/// React's hooks require. (The emit form runs components once and needs
/// none of this.)
public final class Slots {
    var cells: [Cell] = []
    var cursor = 0

    public init() {}

    /// How many states the slots hold.
    public var Count: int { return cells.count }
}

var currentSlots: Slots? = nil

/// Runs body with its States in slots.
public func WithSlots(_ slots: Slots, _ body: () -> void) {
    let prev = currentSlots
    slots.cursor = 0
    currentSlots = slots
    body()
    currentSlots = prev
}

func claimSlot() -> Cell? {
    guard let s = currentSlots, s.cursor < s.cells.count else { return nil }
    let c = s.cells[s.cursor]
    s.cursor += 1
    return c
}

func fillSlot(_ c: Cell) {
    guard let s = currentSlots else { return }
    s.cells.append(c)
    s.cursor += 1
}

/// What some code made that has to end with it: the effects made while it
/// ran, and cleanups registered with OnCleanup. An effect owns what each of
/// its runs makes, and disposes it before running again, so an effect made
/// inside another -- a component's bindings inside a branch -- ends when
/// the branch is gone.
public final class Owner {
    var effects: [Effect] = []
    var cleanups: [() -> void] = []

    public init() {}

    /// Disposes what the owner holds, and empties it.
    public func Dispose() {
        let es = effects
        let cs = cleanups
        effects = []
        cleanups = []
        for e in es { e.Dispose() }
        for c in cs { c() }
    }
}

var currentOwner: Owner? = nil

func own(_ o: Owner?) -> Owner? {
    let prev = currentOwner
    currentOwner = o
    return prev
}

func adopt(_ e: Effect) {
    if let o = currentOwner { o.effects.append(e) }
}

/// Runs body with what it makes owned by owner.
public func WithOwner(_ owner: Owner, _ body: () -> void) {
    let prev = own(owner)
    body()
    _ = own(prev)
}

/// Runs f when the code running now is disposed: its effect runs again,
/// or its owner is disposed.
public func OnCleanup(_ f: () -> void) {
    if let o = currentOwner { o.cleanups.append(f) }
}

/// A value to read, live: a signal, or anything computed from signals.
/// Reading it inside an effect follows what it reads. Its members read
/// through it: `todo.Done` is `todo.Value.Done`.
@dynamicMemberLookup
public struct Readable<T> {
    let get: () -> T

    public init(_ get: () -> T) {
        self.get = get
    }

    public init(_ signal: Signal<T>) {
        let s = signal
        self.get = { s.Value }
    }

    public var Value: T { return get() }

    public subscript<U>(dynamicMember path: KeyPath<T, U>) -> U {
        return get()[keyPath: path]
    }
}
