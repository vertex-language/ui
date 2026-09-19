package webview

import cwindow

/// Modern typography engine backed by platform CoreText / CoreGraphics with bitmap fallback.
public struct FontRenderer {
    /// Measures the dimensions of a text string at a given font size.
    public static func MeasureText(
        _ text: string,
        fontSize: float32,
        bold: bool = false,
        italic: bool = false
    ) -> (width: float32, height: float32) {
        if text.isEmpty {
            return (width: 0.0, height: fontSize * 1.25)
        }
        var w: double = 0.0
        var h: double = 0.0
        cwindow_measure_text(
            text,
            double(fontSize),
            bold ? 1 : 0,
            italic ? 1 : 0,
            &w,
            &h
        )
        if w > 0.0 || h > 0.0 {
            return (width: float32(w), height: float32(h))
        }
        let charWidth = fontSize * 0.75
        let lineHeight = fontSize * 1.25
        return (width: float32(text.utf8.count) * charWidth, height: lineHeight)
    }

    /// Renders a text string into the pixel buffer at (originX, originY).
    public static func DrawText(
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        x: int32,
        y: int32,
        text: string,
        color: Color,
        fontSize: float32,
        scale: float32,
        bold: bool = false,
        italic: bool = false,
        clipX: int32 = 0,
        clipY: int32 = 0,
        clipWidth: int32 = 0,
        clipHeight: int32 = 0
    ) {
        if color.A == 0 || text.isEmpty { return }

        buffer.withUnsafeMutableBufferPointer { bp in
            if let addr = bp.baseAddress {
                cwindow_draw_text(
                    addr,
                    bufferWidth,
                    bufferHeight,
                    x,
                    y,
                    text,
                    double(fontSize),
                    bold ? 1 : 0,
                    italic ? 1 : 0,
                    color.R,
                    color.G,
                    color.B,
                    color.A,
                    double(scale),
                    clipX,
                    clipY,
                    clipWidth,
                    clipHeight
                )
            }
        }
    }

    static func drawChar(
        into buffer: inout [uint8],
        bufferWidth: int32,
        bufferHeight: int32,
        x: int32,
        y: int32,
        ascii: uint8,
        color: Color,
        pixelSize: int32
    ) {
        let glyph = getGlyph(ascii)
        var row = 0
        while row < 8 {
            let rowBits = glyph[row]
            var col = 0
            while col < 5 { // 5x7 font within 8x8 cell
                let mask: uint8 = 1 << uint8(4 - col)
                if (rowBits & mask) != 0 {
                    // Draw a square of size pixelSize x pixelSize
                    var dy: int32 = 0
                    while dy < pixelSize {
                        let py = y + int32(row) * pixelSize + dy
                        if py >= 0 && py < bufferHeight {
                            var dx: int32 = 0
                            while dx < pixelSize {
                                let px = x + int32(col) * pixelSize + dx
                                if px >= 0 && px < bufferWidth {
                                    let idx = int((py * bufferWidth + px) * 4)
                                    if color.A == 255 {
                                        buffer[idx] = color.R
                                        buffer[idx + 1] = color.G
                                        buffer[idx + 2] = color.B
                                        buffer[idx + 3] = 255
                                    } else {
                                        blendPixel(&buffer, idx, color)
                                    }
                                }
                                dx += 1
                            }
                        }
                        dy += 1
                    }
                }
                col += 1
            }
            row += 1
        }
    }

    static func blendPixel(_ buffer: inout [uint8], _ idx: int, _ color: Color) {
        if color.A == 255 {
            buffer[idx] = color.R
            buffer[idx + 1] = color.G
            buffer[idx + 2] = color.B
            buffer[idx + 3] = 255
        } else {
            let alpha = int(color.A)
            let invAlpha = 255 - alpha
            let dstR = int(buffer[idx])
            let dstG = int(buffer[idx + 1])
            let dstB = int(buffer[idx + 2])
            buffer[idx]     = uint8((int(color.R) * alpha + dstR * invAlpha) / 255)
            buffer[idx + 1] = uint8((int(color.G) * alpha + dstG * invAlpha) / 255)
            buffer[idx + 2] = uint8((int(color.B) * alpha + dstB * invAlpha) / 255)
            buffer[idx + 3] = 255
        }
    }

    // 5x7 bitmap patterns for common ASCII characters
    static func getGlyph(_ c: uint8) -> [uint8] {
        // Uppercase letters 'A'...'Z'
        if c == 65 { return [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, 0] } // A
        if c == 66 { return [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E, 0] } // B
        if c == 67 { return [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E, 0] } // C
        if c == 68 { return [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C, 0] } // D
        if c == 69 { return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F, 0] } // E
        if c == 70 { return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10, 0] } // F
        if c == 71 { return [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F, 0] } // G
        if c == 72 { return [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11, 0] } // H
        if c == 73 { return [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0] } // I
        if c == 74 { return [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C, 0] } // J
        if c == 75 { return [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11, 0] } // K
        if c == 76 { return [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F, 0] } // L
        if c == 77 { return [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11, 0] } // M
        if c == 78 { return [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11, 0] } // N
        if c == 79 { return [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0] } // O
        if c == 80 { return [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10, 0] } // P
        if c == 81 { return [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D, 0] } // Q
        if c == 82 { return [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11, 0] } // R
        if c == 83 { return [0x0E, 0x11, 0x10, 0x0E, 0x01, 0x11, 0x0E, 0] } // S
        if c == 84 { return [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0] } // T
        if c == 85 { return [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E, 0] } // U
        if c == 86 { return [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04, 0] } // V
        if c == 87 { return [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11, 0] } // W
        if c == 88 { return [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11, 0] } // X
        if c == 89 { return [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04, 0] } // Y
        if c == 90 { return [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F, 0] } // Z

        // Lowercase letters 'a'...'z'
        if c == 97  { return [0, 0, 0x0E, 0x01, 0x0F, 0x11, 0x0F, 0] } // a
        if c == 98  { return [0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x1E, 0] } // b
        if c == 99  { return [0, 0, 0x0E, 0x10, 0x10, 0x11, 0x0E, 0] } // c
        if c == 100 { return [0x01, 0x01, 0x0D, 0x13, 0x11, 0x11, 0x0F, 0] } // d
        if c == 101 { return [0, 0, 0x0E, 0x11, 0x1F, 0x10, 0x0E, 0] } // e
        if c == 102 { return [0x06, 0x09, 0x08, 0x1C, 0x08, 0x08, 0x08, 0] } // f
        if c == 103 { return [0, 0, 0x0F, 0x11, 0x11, 0x0F, 0x01, 0x0E] } // g
        if c == 104 { return [0x10, 0x10, 0x16, 0x19, 0x11, 0x11, 0x11, 0] } // h
        if c == 105 { return [0x04, 0, 0x0C, 0x04, 0x04, 0x04, 0x0E, 0] } // i
        if c == 106 { return [0x02, 0, 0x06, 0x02, 0x02, 0x12, 0x0C, 0] } // j
        if c == 107 { return [0x10, 0x10, 0x12, 0x14, 0x18, 0x14, 0x12, 0] } // k
        if c == 108 { return [0x0C, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E, 0] } // l
        if c == 109 { return [0, 0, 0x1A, 0x15, 0x15, 0x11, 0x11, 0] } // m
        if c == 110 { return [0, 0, 0x16, 0x19, 0x11, 0x11, 0x11, 0] } // n
        if c == 111 { return [0, 0, 0x0E, 0x11, 0x11, 0x11, 0x0E, 0] } // o
        if c == 112 { return [0, 0, 0x1E, 0x11, 0x1E, 0x10, 0x10, 0] } // p
        if c == 113 { return [0, 0, 0x0D, 0x13, 0x0F, 0x01, 0x01, 0] } // q
        if c == 114 { return [0, 0, 0x16, 0x19, 0x10, 0x10, 0x10, 0] } // r
        if c == 115 { return [0, 0, 0x0F, 0x10, 0x0E, 0x01, 0x1E, 0] } // s
        if c == 116 { return [0x08, 0x08, 0x1C, 0x08, 0x08, 0x09, 0x06, 0] } // t
        if c == 117 { return [0, 0, 0x11, 0x11, 0x11, 0x13, 0x0D, 0] } // u
        if c == 118 { return [0, 0, 0x11, 0x11, 0x11, 0x0A, 0x04, 0] } // v
        if c == 119 { return [0, 0, 0x11, 0x15, 0x15, 0x1B, 0x11, 0] } // w
        if c == 120 { return [0, 0, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0] } // x
        if c == 121 { return [0, 0, 0x11, 0x11, 0x0F, 0x01, 0x0E, 0] } // y
        if c == 122 { return [0, 0, 0x1F, 0x02, 0x04, 0x08, 0x1F, 0] } // z

        // Digits '0'...'9'
        if c == 48 { return [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E, 0] } // 0
        if c == 49 { return [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E, 0] } // 1
        if c == 50 { return [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F, 0] } // 2
        if c == 51 { return [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E, 0] } // 3
        if c == 52 { return [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02, 0] } // 4
        if c == 53 { return [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E, 0] } // 5
        if c == 54 { return [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E, 0] } // 6
        if c == 55 { return [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08, 0] } // 7
        if c == 56 { return [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E, 0] } // 8
        if c == 57 { return [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C, 0] } // 9

        // Punctuation & Symbols
        if c == 33 { return [0x04, 0x04, 0x04, 0x04, 0x04, 0, 0x04, 0] } // !
        if c == 34 { return [0x0A, 0x0A, 0x0A, 0, 0, 0, 0, 0] } // "
        if c == 35 { return [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A, 0] } // #
        if c == 40 { return [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02, 0] } // (
        if c == 41 { return [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08, 0] } // )
        if c == 43 { return [0, 0x04, 0x04, 0x1F, 0x04, 0x04, 0, 0] } // +
        if c == 44 { return [0, 0, 0, 0, 0, 0x04, 0x04, 0x08] } // ,
        if c == 45 { return [0, 0, 0, 0x1F, 0, 0, 0, 0] } // -
        if c == 46 { return [0, 0, 0, 0, 0, 0x04, 0x04, 0] } // .
        if c == 47 { return [0x01, 0x02, 0x02, 0x04, 0x08, 0x08, 0x10, 0] } // /
        if c == 58 { return [0, 0x04, 0x04, 0, 0x04, 0x04, 0, 0] } // :
        if c == 59 { return [0, 0x04, 0x04, 0, 0x04, 0x04, 0x08, 0] } // ;
        if c == 60 { return [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02, 0] } // <
        if c == 61 { return [0, 0x1F, 0, 0x1F, 0, 0, 0, 0] } // =
        if c == 62 { return [0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08, 0] } // >
        if c == 63 { return [0x0E, 0x11, 0x01, 0x02, 0x04, 0, 0x04, 0] } // ?

        // Default empty box
        return [0, 0, 0, 0, 0, 0, 0, 0]
    }
}
