package window

import cwindow

/// What a window shows.
public struct Surface {
    let window: int32
}

/// The window's surface.
public func (w: borrowing Window) Surface() -> Surface {
    return Surface(window: w.Id)
}

/// Shows pixels: `size.Width * size.Height` of them, four bytes each --
/// red, green, blue, alpha, premultiplied -- top row first. They are
/// copied, so the buffer is the caller's again as soon as this returns.
///
/// Size them with `Window.PixelSize` to fill the window at full resolution.
public func (s: borrowing Surface) Present(_ pixels: borrowing [uint8], size: PixelSize) throws {
    let want = int(size.Width) * int(size.Height) * 4
    if size.Width <= 0 || size.Height <= 0 || pixels.count != want {
        throw WindowError.invalidArgument(
            "\(pixels.count) bytes for \(size.Width)x\(size.Height) pixels, which want \(want)")
    }
    let rc = pixels.withUnsafeBufferPointer { bp in
        cwindow_present(s.window, bp.baseAddress, size.Width, size.Height)
    }
    if rc < 0 {
        throw errorFor(rc, "presenting \(size.Width)x\(size.Height) pixels")
    }
}

/// What kind of native objects `RawParts` hands back.
public enum SurfaceKind {
    /// An NSWindow and the NSView that is its content.
    case appKit
}

/// The native objects behind the surface, for a renderer that binds its own
/// swapchain to them and for nothing else. Application code draws with
/// `Present`, or with such a renderer, and never needs this.
public func (s: borrowing Surface) RawParts() -> (kind: SurfaceKind, window: uint64, view: uint64) {
    return (kind: .appKit, window: cwindow_native_window(s.window), view: cwindow_native_view(s.window))
}
