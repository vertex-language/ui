package window

/// A size in points: what a window is measured in, and what input arrives
/// in. A point is a pixel on a standard display and more than one on a
/// high-density one; `Window.ScaleFactor` says how many.
public struct Size {
    public var Width: float32
    public var Height: float32

    public init(_ width: float32, _ height: float32) {
        Width = width
        Height = height
    }
}

/// A size in device pixels: what a surface is measured in. Kept a
/// different type from `Size` so that the two cannot be mixed up.
public struct PixelSize {
    public var Width: int32
    public var Height: int32

    public init(_ width: int32, _ height: int32) {
        Width = width
        Height = height
    }
}

/// A position in points, from the top-left corner.
public struct Point {
    public var X: float32
    public var Y: float32

    public init(_ x: float32, _ y: float32) {
        X = x
        Y = y
    }
}
