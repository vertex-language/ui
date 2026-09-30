// ui/state checked on its own, with no window and no page.
package main

import (
    "time"
    "ui/state"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func testSignals() {
    print("Signals and effects")
    var n = state.Signal(1)
    var seen: [int] = []
    let e = state.Effect { seen.append(n.Value) }
    check(seen == [1], "an effect runs when made")
    n.Value = 2
    check(seen == [1, 2], "and again when what it read is written")
    check(n.Peek() == 2, "Peek reads without following")
    state.Batch {
        n.Value = 3
        n.Value = 4
    }
    check(seen == [1, 2, 4], "writes in a batch run the effect once, after it")
    n.Value = 4
    check(seen == [1, 2, 4], "writing the value it holds tells no one")
    var words = state.Signal(["a"])
    var wordRuns = 0
    _ = state.Effect { wordRuns += 1; _ = words.Value }
    words.Value = ["a"]
    words.Value = ["a", "b"]
    check(wordRuns == 2, "nor does an equal array; a different one does (\(wordRuns))")
    e.Dispose()
    n.Value = 5
    check(seen == [1, 2, 4], "a disposed effect runs no more")
}

func testDependencies() {
    print("What an effect follows is what it read last")
    var flag = state.Signal(true)
    var a = state.Signal("a")
    var b = state.Signal("b")
    var runs = 0
    var last = ""
    _ = state.Effect {
        runs += 1
        last = flag.Value ? a.Value : b.Value
    }
    b.Value = "b2"
    check(runs == 1, "a signal not read is not followed")
    flag.Value = false
    check(runs == 2 && last == "b2", "a branch taken reads the other signal")
    a.Value = "a2"
    check(runs == 2, "and the signal it stopped reading no longer runs it")
    var quiet = state.Signal(0)
    _ = state.Effect {
        runs += 1
        _ = state.Untracked { quiet.Value }
    }
    let before = runs
    quiet.Value = 1
    check(runs == before, "an untracked read is not followed")
}

func testComputed() {
    print("Computed values")
    var xs = state.Signal([1, 2, 3])
    var computes = 0
    let sum = state.Computed<int> {
        computes += 1
        return xs.Value.reduce(0, +)
    }
    check(computes == 0, "a computed value computes nothing until read")
    check(sum.Value == 6 && sum.Value == 6 && computes == 1, "and computes once for many reads")
    var shown: [int] = []
    _ = state.Effect { shown.append(sum.Value * 10) }
    xs.Value = [1, 2, 3, 4]
    check(shown == [60, 100] && computes == 2, "a change reaches an effect through it")
}

func testState() {
    print("@State")
    @state.State var count = 0
    var shown: [int] = []
    _ = state.Effect { shown.append(count) }
    count += 1
    count += 1
    check(shown == [0, 1, 2], "a state variable reads and writes its signal")
    var s = $count
    s.Value = 10
    check(count == 10 && shown.last == 10, "$count is the signal itself")
    let bump = { count += 5 }
    bump()
    check(count == 15 && shown.last == 15, "a closure writes the same state")
}

struct Todo {
    var Title: string
    var Done: bool
}

func testOwners() {
    print("Owners and Readable")
    var show = state.Signal(true)
    var n = state.Signal(0)
    var inner = 0
    var cleaned = 0
    _ = state.Effect {
        if show.Value {
            _ = state.Effect { inner += 1; _ = n.Value }
            state.OnCleanup { cleaned += 1 }
        }
    }
    n.Value = 1
    check(inner == 2, "an effect made inside another runs as its own")
    show.Value = false
    let before = inner
    n.Value = 2
    check(inner == before && cleaned == 1, "and is disposed, with its cleanups, when the outer runs again")

    var todo = state.Signal(Todo(Title: "milk", Done: false))
    let r = state.Readable(todo)
    var seen: [bool] = []
    _ = state.Effect { seen.append(r.Done) }
    todo.Value = Todo(Title: "milk", Done: true)
    check(seen == [false, true] && r.Title == "milk", "a Readable's members read through it, and are followed")
    let doubled = state.Readable<int> { n.Value * 2 }
    check(doubled.Value == 4, "a Readable of an expression")
}

@Observable final class Store {
    var Todos: [Todo] = []
    var Filter = "all"
    var Owner: string
    let Id = 7
    var Left: int { return Todos.filter { !$0.Done }.count }

    init(owner: string) { Owner = owner }

    func Add(_ t: string) { Todos.append(Todo(Title: t, Done: false)) }
    func Toggle(_ i: int) { Todos[i].Done = !Todos[i].Done }
    func Clear() { Todos.removeAll { $0.Done } }
}

func testObservable() {
    let s = Store(owner: "ada")
    var left: [int] = []
    var owners: [string] = []
    _ = state.Effect { left.append(s.Left) }
    _ = state.Effect { owners.append(s.Owner) }
    s.Add("a")
    s.Add("b")
    s.Toggle(0)
    check(left == [0, 1, 2, 1], "an @Observable's properties are followed, through its methods (\(left))")
    s.Filter = "done"
    check(left == [0, 1, 2, 1] && owners == ["ada"], "and each only by what read it")
    var o = s.$Owner
    o.Value = "grace"
    check(owners == ["ada", "grace"] && s.Owner == "grace", "$Owner is the property's signal")
    s.Owner = "grace"
    check(owners.count == 2, "a write of the value it holds tells no one")
    s.Clear()
    check(s.Todos.count == 1 && s.Id == 7, "a let stays a let")
}

struct Oops: Error {}

func fetch(_ n: int) async throws -> int {
    try await time.Sleep(time.Duration.Milliseconds(10))
    if n < 0 { throw Oops() }
    return n * 2
}

func describe(_ l: state.Load<int>) -> string {
    switch l {
    case .loading: return "loading"
    case .ready(let v): return "ready \(v)"
    case .failed(_): return "failed"
    }
}

@MainActor
func testResources() async {
    var id = state.Signal(1)
    let r = state.Resource<int>(of: { id.Value }) { n in try await fetch(n) }
    var seen: [string] = []
    _ = state.Effect { seen.append(describe(r.State)) }
    await r.Loaded()
    id.Value = 5
    await r.Loaded()
    id.Value = -1
    await r.Loaded()
    check(seen == ["loading", "ready 2", "loading", "ready 10", "loading", "failed"], "a resource loads, loads again when its key changes, and fails")
    check(r.Value == nil, "and has no value after a failure")

    var q = state.Signal(1)
    let kept = state.Resource<int>(of: { q.Value }, keepPrevious: true) { n in try await fetch(n) }
    var shown: [string] = []
    _ = state.Effect { shown.append(describe(kept.State) + (kept.IsPending ? "*" : "")) }
    await kept.Loaded()
    q.Value = 2
    q.Value = 3
    await kept.Loaded()
    kept.Reload()
    await kept.Loaded()
    check(shown == ["loading*", "ready 2", "ready 2*", "ready 6", "ready 6*", "ready 6"], "with keepPrevious, the last value shows while the next loads; a superseded load is dropped")

    let o = state.Owner()
    var gone: state.Resource<int>? = nil
    state.WithOwner(o) { gone = state.Resource<int> { try await fetch(7) } }
    o.Dispose()
    await gone!.Loaded()
    check(describe(gone!.State) == "loading", "a disposed resource's load is dropped")
}

@MainActor
func main() async -> int32 {
    testOwners()
    testSignals()
    testDependencies()
    testComputed()
    testState()
    testObservable()
    await testResources()
    if failures > 0 {
        print("\(failures) FAILED")
        return 1
    }
    print("ALL STATE CHECKS PASSED")
    return 0
}
