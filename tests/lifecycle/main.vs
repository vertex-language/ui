// ui/window checked against a real window, with no one at the keyboard.
//
// Each check creates what it needs, drives it from code, and fails loudly:
// the program exits with the number of checks that did not pass. Run it in
// a logged-in session -- a window needs a display.
package main

import window

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

// Geometry: points, pixels, and the ratio between them.
func geometry(_ w: borrowing window.Window) {
    let size = w.Size()
    check(size.Width == 480 && size.Height == 320, "the content area is the size asked for")
    let scale = w.ScaleFactor()
    check(scale >= 1, "the scale factor is at least 1")
    let px = w.PixelSize()
    check(px.Width == int32(480 * scale) && px.Height == int32(320 * scale),
          "pixels are points times the scale factor")
}

// A frame is delivered once per request, through WaitEvent.
func frames(_ w: borrowing window.Window) async {
    var got = 0
    var last: float64 = 0
    var increasing = true
    while got < 3 {
        w.RequestFrame()
        while let e = await w.WaitEvent() {
            if case .frame(let f) = e {
                if f.Time <= last { increasing = false }
                last = f.Time
                got += 1
                break
            }
        }
    }
    check(got == 3, "three frames, one per request")
    check(increasing, "frame times increase")
}

// Presenting pixels: the right number is accepted, the wrong one refused.
func present(_ w: borrowing window.Window) {
    let px = w.PixelSize()
    var pixels = [uint8](repeating: 0, count: int(px.Width) * int(px.Height) * 4)
    var i = 0
    while i < pixels.count {
        pixels[i] = 40
        pixels[i + 1] = 90
        pixels[i + 2] = 160
        pixels[i + 3] = 255
        i += 4
    }
    let surface = w.Surface()
    var presented = true
    do {
        try surface.Present(pixels, size: px)
    } catch {
        presented = false
    }
    check(presented, "presenting a window's worth of pixels")

    var refused = false
    do {
        try surface.Present(pixels, size: window.PixelSize(px.Width + 1, px.Height))
    } catch window.WindowError.invalidArgument(_) {
        refused = true
    } catch {
        refused = false
    }
    check(refused, "presenting the wrong number of pixels is refused")
    let parts = surface.RawParts()
    check(parts.window != 0 && parts.view != 0, "the native objects are there")
}

// Changing the window is reported back as events.
func resize(_ w: borrowing window.Window) async {
    w.SetSize(window.Size(640, 400))
    var resized = false
    while let e = w.PollEvent() {
        if case .resized(let s) = e {
            resized = s.Width == 640 && s.Height == 400
        }
    }
    check(resized, "SetSize is reported as .resized")
    check(w.Size().Width == 640, "and the size reads back")
}

// A task keeps running while another waits on the window.
func concurrency(_ w: borrowing window.Window) async {
    let ticker = Task { () async -> int in
        var ticks = 0
        while ticks < 5 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            ticks += 1
        }
        return ticks
    }
    // Wait on the window meanwhile: a frame arrives after the ticker has
    // had turns, because waiting parks this task rather than the thread.
    w.RequestFrame()
    while let e = await w.WaitEvent() {
        if case .frame(_) = e {
            break
        }
    }
    check(await ticker.value == 5, "a task runs to completion beside a window wait")
}

@_silgen_name("popen")
func c_popen(_ command: UnsafePointer<CChar>!, _ mode: UnsafePointer<CChar>!) -> OpaquePointer?

@_silgen_name("pclose")
func c_pclose(_ stream: OpaquePointer?) -> int32

@_silgen_name("fileno")
func c_fileno(_ stream: OpaquePointer?) -> int32

@_silgen_name("clock_gettime_nsec_np")
func c_clock_nsec(_ clock: uint32) -> uint64

// A monotonic clock, in nanoseconds: CLOCK_UPTIME_RAW.
func now() -> uint64 {
    return c_clock_nsec(8)
}

@_silgen_name("vertex_task_wait_fd")
func waitFd(_ fd: int32, _ events: int32, _ timeoutNanos: int64) async -> int32

// A descriptor a task waits on becomes ready while the thread is asleep in
// the window system's wait, and the thread has to come out of that wait for
// it, not only for a window event. The write comes from another process, a
// fifth of a second later, so nothing on this thread is due in between: no
// task can run, no frame is asked for, and the executor's own poll has seen
// the pipe empty before the thread goes to sleep. The wait has a deadline of
// five seconds so that a thread that never wakes fails the check rather than
// hanging it.
//
// Input ends the window system's wait too -- a mouse moving anywhere on the
// screen is an event for the active app -- so on a machine someone is using,
// the check can pass without the wake, a little late. With no input, a
// missing wake leaves the task waiting until the deadline, and it fails.
func descriptors() async {
    let started = now()
    guard let child = c_popen("sleep 0.2; printf x", "r") else {
        check(false, "a child process writes to a pipe")
        return
    }
    let ready = await waitFd(c_fileno(child), 1, 5_000_000_000)
    let waited = (now() - started) / 1_000_000
    _ = c_pclose(child)
    print("      woke \(waited) ms after the child started")
    check(ready > 0 && waited < 2_000,
          "a task waiting on a pipe wakes while the thread sleeps in the window system")
}

func main() async -> int32 {
    var options = window.Options()
    options.Resizable = false
    let w: window.Window
    do {
        w = try window.Create(title: "lifecycle", size: window.Size(480, 320), options: options)
    } catch let e as window.WindowError {
        print("FAIL  create: \(e.Message)")
        return 1
    } catch {
        return 1
    }
    check(w.Id > 0, "a window is made")
    geometry(w)
    await frames(w)
    present(w)
    await resize(w)
    await concurrency(w)
    await descriptors()
    w.SetTitle("lifecycle: closing")
    w.Close()
    print(failures == 0 ? "all passed" : "\(failures) failed")
    return int32(failures)
}
