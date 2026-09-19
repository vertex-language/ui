package webview

/// An 8-bit RGBA color representation.
public struct Color: Equatable {
    public var R: uint8
    public var G: uint8
    public var B: uint8
    public var A: uint8

    public init(_ r: uint8, _ g: uint8, _ b: uint8, _ a: uint8 = 255) {
        self.R = r
        self.G = g
        self.B = b
        self.A = a
    }

    public static let transparent = Color(0, 0, 0, 0)
    public static let black       = Color(0, 0, 0, 255)
    public static let white       = Color(255, 255, 255, 255)
    public static let red         = Color(230, 40, 40, 255)
    public static let green       = Color(40, 180, 40, 255)
    public static let blue        = Color(9, 105, 218, 255)
    public static let gray        = Color(128, 128, 128, 255)
    public static let lightGray   = Color(240, 242, 245, 255)
    public static let darkGray    = Color(36, 41, 47, 255)
    public static let borderGray  = Color(210, 215, 220, 255)

    /// Parses a CSS color string like "#fff", "#0969da", "rgb(255,0,0)", or named color.
    public static func Parse(_ colorStr: string) -> Color {
        let str = trimString(toLower(colorStr))
        if str.isEmpty || str == "transparent" { return .transparent }
        if str == "black" { return .black }
        if str == "white" { return .white }
        if str == "red"   { return .red }
        if str == "green" { return .green }
        if str == "blue"  { return .blue }
        if str == "gray"  { return .gray }

        let bytes = bytesFromString(str)

        // Hex color: #rgb or #rrggbb
        if bytes.count > 0 && bytes[0] == 35 { // '#'
            if bytes.count == 4 { // #rgb
                let r = hexVal(bytes[1]) * 17
                let g = hexVal(bytes[2]) * 17
                let b = hexVal(bytes[3]) * 17
                return Color(r, g, b, 255)
            }
            if bytes.count == 7 { // #rrggbb
                let r = hexVal(bytes[1]) * 16 + hexVal(bytes[2])
                let g = hexVal(bytes[3]) * 16 + hexVal(bytes[4])
                let b = hexVal(bytes[5]) * 16 + hexVal(bytes[6])
                return Color(r, g, b, 255)
            }
            if bytes.count == 9 { // #rrggbbaa
                let r = hexVal(bytes[1]) * 16 + hexVal(bytes[2])
                let g = hexVal(bytes[3]) * 16 + hexVal(bytes[4])
                let b = hexVal(bytes[5]) * 16 + hexVal(bytes[6])
                let a = hexVal(bytes[7]) * 16 + hexVal(bytes[8])
                return Color(r, g, b, a)
            }
        }

        // Default fallback to black
        return .black
    }
}

func hexVal(_ b: uint8) -> uint8 {
    if b >= 48 && b <= 57 { return b - 48 }         // '0'...'9'
    if b >= 97 && b <= 102 { return b - 97 + 10 }   // 'a'...'f'
    if b >= 65 && b <= 70 { return b - 65 + 10 }    // 'A'...'F'
    return 0
}
