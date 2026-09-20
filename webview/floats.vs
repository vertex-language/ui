package webview

/// A float placed in a block formatting context: its margin box, in the
/// context root's coordinates.
struct PlacedFloat {
    var box: Box
    var left: bool
    var x: float32
    var y: float32
    var width: float32
    var height: float32

    var right: float32 { return x + width }
    var bottom: float32 { return y + height }
}

/// The floats of one block formatting context, which lines in it flow
/// around and blocks in it clear.
final class FloatContext {
    var floats: [PlacedFloat] = []

    init() {}

    /// How far floats reach into a band of rows: the right edge of the
    /// left floats and the left edge of the right floats in it, or the
    /// context's own edges where none reach.
    func intrusions(y: float32, height: float32, left: float32, right: float32) -> (left: float32, right: float32) {
        var l = left
        var r = right
        for f in floats {
            if f.y < y + height && f.bottom > y {
                if f.left {
                    if f.right > l { l = f.right }
                } else {
                    if f.x < r { r = f.x }
                }
            }
        }
        return (left: l, right: r)
    }

    /// The first row below y at which the floats reaching y change,
    /// where a line that does not fit beside them can try again.
    func nextBand(after y: float32) -> float32? {
        var next: float32? = nil
        for f in floats {
            if f.bottom > y {
                if next == nil || f.bottom < next! { next = f.bottom }
            }
        }
        return next
    }

    /// The row below every float of a side, for `clear`.
    func clearance(_ clear: Clear, at y: float32) -> float32 {
        var out = y
        for f in floats {
            let matches = clear == .both || (clear == .left && f.left) || (clear == .right && !f.left)
            if matches && f.bottom > out { out = f.bottom }
        }
        return out
    }

    /// The lowest bottom edge, for a root that grows to hold its floats.
    var bottom: float32 {
        var out: float32 = 0
        for f in floats where f.bottom > out { out = f.bottom }
        return out
    }

    /// Places a float as high as it goes, no higher than y, between the
    /// container's edges, beside the floats already there; a float that
    /// fits beside nothing moves down past them.
    func place(_ box: Box, left isLeft: bool, y startY: float32, containerLeft: float32, containerRight: float32) -> PlacedFloat {
        let w = box.OuterWidth
        let h = box.OuterHeight
        var y = startY
        // A float never sits above an earlier one of the same side, nor
        // above the top of any earlier float.
        for f in floats {
            if f.left == isLeft && f.y > y { y = f.y }
        }
        var rounds = 0
        while rounds < 64 {
            rounds += 1
            let band = intrusions(y: y, height: h > 0 ? h : 1, left: containerLeft, right: containerRight)
            if band.right - band.left >= w - 0.01 || nextBand(after: y) == nil {
                let x = isLeft ? band.left : band.right - w
                let placed = PlacedFloat(box: box, left: isLeft, x: x, y: y, width: w, height: h)
                floats.append(placed)
                return placed
            }
            guard let next = nextBand(after: y) else { break }
            y = next
        }
        let placed = PlacedFloat(box: box, left: isLeft, x: isLeft ? containerLeft : containerRight - w, y: y, width: w, height: h)
        floats.append(placed)
        return placed
    }
}

/// Where a box is being laid out: the positioned ancestor its absolute
/// descendants attach to, the floats of its formatting context, and its
/// border-box corner in that context's coordinates.
struct Flow {
    var positioned: Box
    var floats: FloatContext
    var x: float32
    var y: float32

    /// The flow for a child at a corner relative to this box.
    func at(_ dx: float32, _ dy: float32) -> Flow {
        return Flow(positioned: positioned, floats: floats, x: x + dx, y: y + dy)
    }

    /// The flow inside a box that is a formatting root: floats of its
    /// own, coordinates from its corner.
    func root(_ box: Box) -> Flow {
        return Flow(positioned: box.Style.IsPositioned ? box : positioned, floats: FloatContext(), x: 0, y: 0)
    }

    func positionedBy(_ box: Box) -> Flow {
        return Flow(positioned: box, floats: floats, x: x, y: y)
    }
}
