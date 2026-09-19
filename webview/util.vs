package webview

import "ui/draw"

func isSpaceByte(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

/// The text with each run of whitespace made one space, or nothing at
/// its ends when asked; what `white-space: normal` shows.
func collapseSpaces(_ bytes: [uint8]) -> [uint8] {
    var out: [uint8] = []
    var inSpace = false
    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if isSpaceByte(b) {
            if !inSpace {
                out.append(32)
                inSpace = true
            }
        } else {
            out.append(b)
            inSpace = false
        }
        i += 1
    }
    return out
}

func upperBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var i = 0
    while i < out.count {
        if out[i] >= 97 && out[i] <= 122 { out[i] = out[i] - 32 }
        i += 1
    }
    return out
}

func lowerBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var i = 0
    while i < out.count {
        if out[i] >= 65 && out[i] <= 90 { out[i] = out[i] + 32 }
        i += 1
    }
    return out
}

func capitalizeBytes(_ b: [uint8]) -> [uint8] {
    var out = b
    var atStart = true
    var i = 0
    while i < out.count {
        if isSpaceByte(out[i]) {
            atStart = true
        } else {
            if atStart && out[i] >= 97 && out[i] <= 122 { out[i] = out[i] - 32 }
            atStart = false
        }
        i += 1
    }
    return out
}

func roundf(_ v: float32) -> float32 {
    return float32(draw.roundToInt(v))
}

@_silgen_name("floorf")
func c_floorf(_ x: float32) -> float32

@_silgen_name("ceilf")
func c_ceilf(_ x: float32) -> float32

func floorf(_ v: float32) -> float32 { return c_floorf(v) }
func ceilf(_ v: float32) -> float32 { return c_ceilf(v) }

func clampf(_ v: float32, _ lo: float32, _ hi: float32) -> float32 {
    if v < lo { return lo }
    if v > hi { return hi }
    return v
}

/// A number as CSS would print it: whole where it is whole.
func formatNumber(_ v: float32) -> string {
    let i = int(v)
    if float32(i) == v { return "\(i)" }
    return "\(v)"
}

/// Roman numerals for list markers.
func roman(_ n: int, upper: bool) -> string {
    if n <= 0 || n >= 4000 { return "\(n)" }
    let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    let lowerSymbols = ["m", "cm", "d", "cd", "c", "xc", "l", "xl", "x", "ix", "v", "iv", "i"]
    let upperSymbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
    var out = ""
    var rest = n
    var i = 0
    while i < values.count {
        while rest >= values[i] {
            out += upper ? upperSymbols[i] : lowerSymbols[i]
            rest -= values[i]
        }
        i += 1
    }
    return out
}

/// Letters for list markers: a, b, ... z, aa, ab.
func alpha(_ n: int, upper: bool) -> string {
    if n <= 0 { return "\(n)" }
    var bytes: [uint8] = []
    var rest = n
    while rest > 0 {
        let d = uint8((rest - 1) % 26)
        bytes.insert((upper ? 65 : 97) + d, at: 0)
        rest = (rest - 1) / 26
    }
    return draw.stringOf(bytes, 0, bytes.count)
}
