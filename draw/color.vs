package draw

/// A color: red, green, blue and alpha, each 0 to 255, not premultiplied.
public struct Color: Equatable {
    public var R: uint8
    public var G: uint8
    public var B: uint8
    public var A: uint8

    public init(_ r: uint8, _ g: uint8, _ b: uint8, _ a: uint8 = 255) {
        R = r
        G = g
        B = b
        A = a
    }

    public static let transparent = Color(0, 0, 0, 0)
    public static let black = Color(0, 0, 0)
    public static let white = Color(255, 255, 255)

    public var IsOpaque: bool { return A == 255 }
    public var IsTransparent: bool { return A == 0 }

    /// The color with its alpha multiplied by a factor from 0 to 1.
    public func Faded(_ opacity: float32) -> Color {
        if opacity >= 1 { return self }
        if opacity <= 0 { return Color(R, G, B, 0) }
        return Color(R, G, B, uint8(float32(A) * opacity + 0.5))
    }

    /// The pixel the color is on a canvas: premultiplied, R in the low byte.
    public func Premultiplied() -> uint32 {
        if A == 255 {
            return uint32(R) | (uint32(G) << 8) | (uint32(B) << 16) | 0xFF000000
        }
        let a = uint32(A)
        let r = mul255(uint32(R), a)
        let g = mul255(uint32(G), a)
        let b = mul255(uint32(B), a)
        return r | (g << 8) | (b << 16) | (a << 24)
    }

    /// Parses a CSS color: `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`,
    /// `rgb()`, `rgba()`, `hsl()`, `hsla()`, `transparent` and the named
    /// colors. Nil for anything else (including `currentcolor`, which
    /// the caller knows and this does not).
    public static func Parse(_ text: string) -> Color? {
        let bytes = asciiLower(trimmed(text))
        let n = bytes.count
        if n == 0 { return nil }
        if bytes[0] == 35 { // '#'
            return parseHex(bytes)
        }
        if n > 4 && bytes[n - 1] == 41 { // ')'
            if startsWith(bytes, "rgb(") { return parseRGB(bytes, from: 4) }
            if startsWith(bytes, "rgba(") { return parseRGB(bytes, from: 5) }
            if startsWith(bytes, "hsl(") { return parseHSL(bytes, from: 4) }
            if startsWith(bytes, "hsla(") { return parseHSL(bytes, from: 5) }
            return nil
        }
        let name = stringOf(bytes, 0, n)
        if name == "transparent" { return Color.transparent }
        if let packed = namedColors[name] {
            return Color(uint8(packed >> 16), uint8((packed >> 8) & 0xFF), uint8(packed & 0xFF))
        }
        return nil
    }
}

/// x * y / 255, rounded, for x and y in 0...255.
public func mul255(_ x: uint32, _ y: uint32) -> uint32 {
    let t = x * y + 128
    return (t + (t >> 8)) >> 8
}

func parseHex(_ b: [uint8]) -> Color? {
    var digits: [uint8] = []
    var i = 1
    while i < b.count {
        let v = hexValue(b[i])
        if v < 0 { return nil }
        digits.append(uint8(v))
        i += 1
    }
    switch digits.count {
    case 3:
        return Color(digits[0] * 17, digits[1] * 17, digits[2] * 17)
    case 4:
        return Color(digits[0] * 17, digits[1] * 17, digits[2] * 17, digits[3] * 17)
    case 6:
        return Color(digits[0] * 16 + digits[1], digits[2] * 16 + digits[3], digits[4] * 16 + digits[5])
    case 8:
        return Color(digits[0] * 16 + digits[1], digits[2] * 16 + digits[3],
                     digits[4] * 16 + digits[5], digits[6] * 16 + digits[7])
    default:
        return nil
    }
}

func hexValue(_ c: uint8) -> int {
    if c >= 48 && c <= 57 { return int(c - 48) }
    if c >= 97 && c <= 102 { return int(c - 97 + 10) }
    if c >= 65 && c <= 70 { return int(c - 65 + 10) }
    return -1
}

/// The numbers between the parentheses of a functional color, each with
/// whether it was written as a percentage. Commas, spaces and a `/`
/// before the alpha all separate.
func numbersIn(_ b: [uint8], from start: int) -> (values: [float32], percents: [bool]) {
    var values: [float32] = []
    var percents: [bool] = []
    var i = start
    let end = b.count - 1
    while i < end {
        let c = b[i]
        if c == 32 || c == 44 || c == 47 || c == 9 || c == 10 { i += 1; continue }
        var j = i
        while j < end && b[j] != 32 && b[j] != 44 && b[j] != 47 && b[j] != 9 && b[j] != 10 { j += 1 }
        var isPercent = false
        var k = j
        if k > i && b[k - 1] == 37 { isPercent = true; k -= 1 }
        values.append(parseNumber(b, i, k))
        percents.append(isPercent)
        i = j
    }
    return (values: values, percents: percents)
}

func parseRGB(_ b: [uint8], from start: int) -> Color? {
    let parts = numbersIn(b, from: start)
    if parts.values.count < 3 { return nil }
    var channels: [uint8] = []
    var i = 0
    while i < 3 {
        var v = parts.values[i]
        if parts.percents[i] { v = v * 255 / 100 }
        channels.append(clampByte(v))
        i += 1
    }
    var alpha: uint8 = 255
    if parts.values.count >= 4 {
        var a = parts.values[3]
        if parts.percents[3] { a = a / 100 }
        alpha = clampByte(a * 255)
    }
    return Color(channels[0], channels[1], channels[2], alpha)
}

func parseHSL(_ b: [uint8], from start: int) -> Color? {
    let parts = numbersIn(b, from: start)
    if parts.values.count < 3 { return nil }
    var h = parts.values[0]
    while h < 0 { h += 360 }
    while h >= 360 { h -= 360 }
    let s = clamp01(parts.values[1] / 100)
    let l = clamp01(parts.values[2] / 100)
    let c = (1 - absf(2 * l - 1)) * s
    let hp = h / 60
    let x = c * (1 - absf(modf2(hp) - 1))
    var r: float32 = 0
    var g: float32 = 0
    var bl: float32 = 0
    if hp < 1 { r = c; g = x } else if hp < 2 { r = x; g = c } else if hp < 3 { g = c; bl = x }
    else if hp < 4 { g = x; bl = c } else if hp < 5 { r = x; bl = c } else { r = c; bl = x }
    let m = l - c / 2
    var alpha: uint8 = 255
    if parts.values.count >= 4 {
        var a = parts.values[3]
        if parts.percents[3] { a = a / 100 }
        alpha = clampByte(a * 255)
    }
    return Color(clampByte((r + m) * 255), clampByte((g + m) * 255), clampByte((bl + m) * 255), alpha)
}

func modf2(_ v: float32) -> float32 {
    var x = v
    while x >= 2 { x -= 2 }
    while x < 0 { x += 2 }
    return x
}

func absf(_ v: float32) -> float32 { return v < 0 ? -v : v }
func clamp01(_ v: float32) -> float32 { return v < 0 ? 0 : (v > 1 ? 1 : v) }

func clampByte(_ v: float32) -> uint8 {
    if v <= 0 { return 0 }
    if v >= 255 { return 255 }
    return uint8(v + 0.5)
}

/// A decimal number, with an optional sign, point and exponent, read
/// from bytes[i..<end]; anything else there ends it.
public func parseNumber(_ b: [uint8], _ start: int, _ end: int) -> float32 {
    var i = start
    var negative = false
    if i < end && (b[i] == 45 || b[i] == 43) { negative = b[i] == 45; i += 1 }
    var value: float32 = 0
    while i < end && b[i] >= 48 && b[i] <= 57 {
        value = value * 10 + float32(b[i] - 48)
        i += 1
    }
    if i < end && b[i] == 46 {
        i += 1
        var scale: float32 = 0.1
        while i < end && b[i] >= 48 && b[i] <= 57 {
            value += float32(b[i] - 48) * scale
            scale *= 0.1
            i += 1
        }
    }
    if i < end && (b[i] == 101 || b[i] == 69) {
        i += 1
        var expNegative = false
        if i < end && (b[i] == 45 || b[i] == 43) { expNegative = b[i] == 45; i += 1 }
        var exp = 0
        while i < end && b[i] >= 48 && b[i] <= 57 {
            exp = exp * 10 + int(b[i] - 48)
            i += 1
        }
        var k = 0
        while k < exp {
            if expNegative { value *= 0.1 } else { value *= 10 }
            k += 1
        }
    }
    return negative ? -value : value
}

func startsWith(_ b: [uint8], _ prefix: string) -> bool {
    let p = [uint8](prefix.utf8)
    if p.count > b.count { return false }
    var i = 0
    while i < p.count {
        if b[i] != p[i] { return false }
        i += 1
    }
    return true
}

func trimmed(_ s: string) -> [uint8] {
    let b = [uint8](s.utf8)
    var start = 0
    var end = b.count
    while start < end && isSpace(b[start]) { start += 1 }
    while end > start && isSpace(b[end - 1]) { end -= 1 }
    var out: [uint8] = []
    var i = start
    while i < end { out.append(b[i]); i += 1 }
    return out
}

func isSpace(_ c: uint8) -> bool { return c == 32 || c == 9 || c == 10 || c == 13 || c == 12 }

func asciiLower(_ b: [uint8]) -> [uint8] {
    var out = b
    var i = 0
    while i < out.count {
        if out[i] >= 65 && out[i] <= 90 { out[i] = out[i] + 32 }
        i += 1
    }
    return out
}

@_silgen_name("vertex_string_from_utf8")
func stringFromUtf8(_ ptr: UnsafeRawPointer, _ count: int64) -> string

/// The string bytes[start..<end] spell.
public func stringOf(_ bytes: [uint8], _ start: int, _ end: int) -> string {
    if start >= end { return "" }
    return bytes.withUnsafeBytes { bp in
        stringFromUtf8(bp.baseAddress! + start, int64(end - start))
    }
}

// The named colors of CSS Color Level 4, as 0xRRGGBB.
let namedColors: [string: uint32] = [
    "aliceblue": 0xF0F8FF, "antiquewhite": 0xFAEBD7, "aqua": 0x00FFFF, "aquamarine": 0x7FFFD4,
    "azure": 0xF0FFFF, "beige": 0xF5F5DC, "bisque": 0xFFE4C4, "black": 0x000000,
    "blanchedalmond": 0xFFEBCD, "blue": 0x0000FF, "blueviolet": 0x8A2BE2, "brown": 0xA52A2A,
    "burlywood": 0xDEB887, "cadetblue": 0x5F9EA0, "chartreuse": 0x7FFF00, "chocolate": 0xD2691E,
    "coral": 0xFF7F50, "cornflowerblue": 0x6495ED, "cornsilk": 0xFFF8DC, "crimson": 0xDC143C,
    "cyan": 0x00FFFF, "darkblue": 0x00008B, "darkcyan": 0x008B8B, "darkgoldenrod": 0xB8860B,
    "darkgray": 0xA9A9A9, "darkgreen": 0x006400, "darkgrey": 0xA9A9A9, "darkkhaki": 0xBDB76B,
    "darkmagenta": 0x8B008B, "darkolivegreen": 0x556B2F, "darkorange": 0xFF8C00, "darkorchid": 0x9932CC,
    "darkred": 0x8B0000, "darksalmon": 0xE9967A, "darkseagreen": 0x8FBC8F, "darkslateblue": 0x483D8B,
    "darkslategray": 0x2F4F4F, "darkslategrey": 0x2F4F4F, "darkturquoise": 0x00CED1, "darkviolet": 0x9400D3,
    "deeppink": 0xFF1493, "deepskyblue": 0x00BFFF, "dimgray": 0x696969, "dimgrey": 0x696969,
    "dodgerblue": 0x1E90FF, "firebrick": 0xB22222, "floralwhite": 0xFFFAF0, "forestgreen": 0x228B22,
    "fuchsia": 0xFF00FF, "gainsboro": 0xDCDCDC, "ghostwhite": 0xF8F8FF, "gold": 0xFFD700,
    "goldenrod": 0xDAA520, "gray": 0x808080, "green": 0x008000, "greenyellow": 0xADFF2F,
    "grey": 0x808080, "honeydew": 0xF0FFF0, "hotpink": 0xFF69B4, "indianred": 0xCD5C5C,
    "indigo": 0x4B0082, "ivory": 0xFFFFF0, "khaki": 0xF0E68C, "lavender": 0xE6E6FA,
    "lavenderblush": 0xFFF0F5, "lawngreen": 0x7CFC00, "lemonchiffon": 0xFFFACD, "lightblue": 0xADD8E6,
    "lightcoral": 0xF08080, "lightcyan": 0xE0FFFF, "lightgoldenrodyellow": 0xFAFAD2, "lightgray": 0xD3D3D3,
    "lightgreen": 0x90EE90, "lightgrey": 0xD3D3D3, "lightpink": 0xFFB6C1, "lightsalmon": 0xFFA07A,
    "lightseagreen": 0x20B2AA, "lightskyblue": 0x87CEFA, "lightslategray": 0x778899, "lightslategrey": 0x778899,
    "lightsteelblue": 0xB0C4DE, "lightyellow": 0xFFFFE0, "lime": 0x00FF00, "limegreen": 0x32CD32,
    "linen": 0xFAF0E6, "magenta": 0xFF00FF, "maroon": 0x800000, "mediumaquamarine": 0x66CDAA,
    "mediumblue": 0x0000CD, "mediumorchid": 0xBA55D3, "mediumpurple": 0x9370DB, "mediumseagreen": 0x3CB371,
    "mediumslateblue": 0x7B68EE, "mediumspringgreen": 0x00FA9A, "mediumturquoise": 0x48D1CC, "mediumvioletred": 0xC71585,
    "midnightblue": 0x191970, "mintcream": 0xF5FFFA, "mistyrose": 0xFFE4E1, "moccasin": 0xFFE4B5,
    "navajowhite": 0xFFDEAD, "navy": 0x000080, "oldlace": 0xFDF5E6, "olive": 0x808000,
    "olivedrab": 0x6B8E23, "orange": 0xFFA500, "orangered": 0xFF4500, "orchid": 0xDA70D6,
    "palegoldenrod": 0xEEE8AA, "palegreen": 0x98FB98, "paleturquoise": 0xAFEEEE, "palevioletred": 0xDB7093,
    "papayawhip": 0xFFEFD5, "peachpuff": 0xFFDAB9, "peru": 0xCD853F, "pink": 0xFFC0CB,
    "plum": 0xDDA0DD, "powderblue": 0xB0E0E6, "purple": 0x800080, "rebeccapurple": 0x663399,
    "red": 0xFF0000, "rosybrown": 0xBC8F8F, "royalblue": 0x4169E1, "saddlebrown": 0x8B4513,
    "salmon": 0xFA8072, "sandybrown": 0xF4A460, "seagreen": 0x2E8B57, "seashell": 0xFFF5EE,
    "sienna": 0xA0522D, "silver": 0xC0C0C0, "skyblue": 0x87CEEB, "slateblue": 0x6A5ACD,
    "slategray": 0x708090, "slategrey": 0x708090, "snow": 0xFFFAFA, "springgreen": 0x00FF7F,
    "steelblue": 0x4682B4, "tan": 0xD2B48C, "teal": 0x008080, "thistle": 0xD8BFD8,
    "tomato": 0xFF6347, "turquoise": 0x40E0D0, "violet": 0xEE82EE, "wheat": 0xF5DEB3,
    "white": 0xFFFFFF, "whitesmoke": 0xF5F5F5, "yellow": 0xFFFF00, "yellowgreen": 0x9ACD32,
]
