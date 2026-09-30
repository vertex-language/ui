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

    /// Writes a value; one equal to what the cell holds tells no one, so
    /// `count = count` runs nothing.
    func write(_ v: Any, same: bool) {
        value = v
        if same { return }
        self.changed()
        written()
    }
}

/// Whether two values a cell holds are equal, where their type says what
/// that is: the numbers, strings and Booleans, and arrays of them. Any
/// other type is never equal, so writing it always tells what read it.
/// Generic, so it is compiled where the value's type is: vsc does not yet
/// cast an array boxed in another module.
func equal<T>(_ a: Any, _ b: T) -> bool {
    if let x = a as? int, let y = b as? int { return x == y }
    if let x = a as? string, let y = b as? string { return x == y }
    if let x = a as? bool, let y = b as? bool { return x == y }
    if let x = a as? float64, let y = b as? float64 { return x == y }
    if let x = a as? float32, let y = b as? float32 { return x == y }
    if let x = a as? int32, let y = b as? int32 { return x == y }
    if let x = a as? int64, let y = b as? int64 { return x == y }
    if let x = a as? uint8, let y = b as? uint8 { return x == y }
    if let x = a as? [int], let y = b as? [int] { return x == y }
    if let x = a as? [string], let y = b as? [string] { return x == y }
    return false
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

    /// A signal with no value yet: an @Observable property set only in its
    /// class's init starts as one. Reading it before it is set is an error.
    public init() {
        cell = Cell(Unset())
    }

    init(cell: Cell) {
        self.cell = cell
    }

    public var Value: T {
        get { return cell.read() as! T }
        set { cell.write(newValue, same: equal(cell.value, newValue)) }
    }

    /// The value, without following it.
    public func Peek() -> T { return cell.value as! T }
}

/// What an empty signal holds.
public struct Unset {}

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
        signal = Signal<T>(wrappedValue)
    }

    public var wrappedValue: T {
        get { return signal.Value }
        set { signal.Value = newValue }
    }

    public var projectedValue: Signal<T> { return signal }
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

/// The owner of what the code running now makes, if any: to make
/// something later -- after an await, once mounted -- that ends with it.
public func CurrentOwner() -> Owner? { return currentOwner }

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

// MARK: - Resource

/// Where an async value is: still loading, loaded, or failed.
public enum Load<T> {
    case loading
    case ready(T)
    case failed(Error)
}

/// A value loaded asynchronously, as state: `State` is `.loading`, then
/// `.ready(value)` or `.failed(error)`, and what reads it follows it.
///
///     let user = state.Resource(of: { id }) { id in try await api.User(id) }
///     {switch user.State { case .loading: <Spinner/> case .ready(let u): … }}
///
/// The load runs off the main thread and its result is written on it. When
/// the key -- what `of` reads -- changes, the load in flight is cancelled
/// and a new one started; when the code that made the resource is
/// disposed (a component gone), so is its load. With keepPrevious, a
/// reload keeps the last value showing, and IsPending says it is under way.
public struct Resource<T> {
    var signal: Signal<LoadBox<T>>
    var pending: Signal<bool>
    let job: Job

    /// A resource loaded again when what key reads changes.
    public init<K>(of key: () -> K, keepPrevious: bool = false, _ load: (K) async throws -> T) {
        signal = Signal<LoadBox<T>>(LoadBox<T>(Load<T>.loading))
        pending = Signal<bool>(true)
        job = newJob()
        let sig = signal
        let busy = pending
        let j = job
        _ = Effect {
            let k = key()
            Untracked {
                j.start {
                    var s = sig
                    var p = busy
                    Batch {
                        if !keepPrevious || !isReady(s.Peek().load) { s.Value = LoadBox<T>(Load<T>.loading) }
                        p.Value = true
                    }
                    let generation = j.generation
                    return Task { @MainActor in
                        do {
                            let v = try await load(k)
                            if j.generation == generation {
                                Batch {
                                    s.Value = LoadBox<T>(Load<T>.ready(v))
                                    p.Value = false
                                }
                            }
                        } catch {
                            let failed = LoadBox<T>(Load<T>.failed(error))
                            if j.generation == generation {
                                Batch {
                                    s.Value = failed
                                    p.Value = false
                                }
                            }
                        }
                    }
                }
            }
            OnCleanup { j.cancel() }
        }
    }

    /// A resource loaded once, and again on Reload.
    public init(keepPrevious: bool = false, _ load: () async throws -> T) {
        self.init(of: { 0 }, keepPrevious: keepPrevious, { _ in try await load() })
    }

    /// Where the value is: followed.
    public var State: Load<T> { return signal.Value.load }

    /// The value, once loaded; nil while loading or after a failure.
    public var Value: T? {
        if case .ready(let v) = signal.Value.load { return v }
        return nil
    }

    /// Whether a load is under way.
    public var IsPending: bool { return pending.Value }

    /// Loads again, with the key as it is.
    public func Reload() { job.restart() }

    /// Waits for the load under way to end: for tests, and for code that
    /// needs the value before it goes on.
    public func Loaded() async { await job.wait() }
}

/// A Load in a box: a signal holds a class, where it cannot yet hold an
/// enum with a payload (vsc_TODO.md #13).
final class LoadBox<T> {
    let load: Load<T>
    init(_ l: Load<T>) { load = l }
}

func isReady<T>(_ l: Load<T>) -> bool {
    if case .ready(_) = l { return true }
    return false
}

func newJob() -> Job { return Job() }

/// A resource's load: the task under way, how many have been started (a
/// result from an older one is dropped), and how to start another.
final class Job {
    var task: Task<Void, Never>? = nil
    var generation = 0
    var starter: (() -> Task<Void, Never>)? = nil

    init() {}

    func start(_ f: () -> Task<Void, Never>) {
        starter = f
        restart()
    }

    func restart() {
        task?.cancel()
        generation += 1
        if let f = starter { task = f() }
    }

    func cancel() {
        task?.cancel()
        generation += 1
        task = nil
    }

    func wait() async {
        if let t = task { await t.value }
    }
}
