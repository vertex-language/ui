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
    // Converted, since uint64_t imports as UInt64 on Darwin and, being
    // unsigned long there, as UInt on Linux and Android.
    return (kind: .appKit, window: uint64(cwindow_native_window(s.window)),
            view: uint64(cwindow_native_view(s.window)))
}

/// Copies a rectangular block of premultiplied RGBA8 pixels from `source` into `destination`.
/// `origin` specifies the top-left offset in destination pixels where the source will be placed.
public func Blit(
    source: borrowing [uint8],
    sourceSize: PixelSize,
    destination: inout [uint8],
    destinationSize: PixelSize,
    at origin: Point,
    scale: float32 = 1.0
) {
    let destX = int(origin.X * scale)
    let destY = int(origin.Y * scale)
    let srcW = int(sourceSize.Width)
    let srcH = int(sourceSize.Height)
    let dstW = int(destinationSize.Width)
    let dstH = int(destinationSize.Height)

    var row = 0
    while row < srcH {
        let y = destY + row
        if y >= 0 && y < dstH {
            var col = 0
            while col < srcW {
                let x = destX + col
                if x >= 0 && x < dstW {
                    let srcIdx = (row * srcW + col) * 4
                    let dstIdx = (y * dstW + x) * 4
                    destination[dstIdx] = source[srcIdx]
                    destination[dstIdx + 1] = source[srcIdx + 1]
                    destination[dstIdx + 2] = source[srcIdx + 2]
                    destination[dstIdx + 3] = source[srcIdx + 3]
                }
                col += 1
            }
        }
        row += 1
    }
}

