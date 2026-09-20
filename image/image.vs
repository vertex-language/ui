package image

import cimage
import "ui/draw"

/// Decodes an image's bytes -- PNG, JPEG, GIF, WebP and whatever else
/// the platform reads -- into pixels a canvas can draw. Nil where the
/// bytes are not an image.
public func Decode(_ bytes: [uint8]) -> draw.Image? {
    if bytes.isEmpty { return nil }
    var width: int32 = 0
    var height: int32 = 0
    let need = bytes.withUnsafeBytes { bp in
        cimage_decode(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), &width, &height, nil, 0)
    }
    if need <= 0 || width <= 0 || height <= 0 { return nil }
    var pixels = [uint8](repeating: 0, count: int(need))
    let got = bytes.withUnsafeBytes { bp in
        pixels.withUnsafeMutableBufferPointer { pp in
            cimage_decode(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), &width, &height, pp.baseAddress!, int32(pp.count))
        }
    }
    if got != need { return nil }
    return draw.Image(width: width, height: height, pixels: pixels)
}

/// Decodes a `data:` URL's image, base64 or plain.
public func DecodeDataURL(_ url: string) -> draw.Image? {
    let b = [uint8](url.utf8)
    if b.count < 6 { return nil }
    var comma = 0
    while comma < b.count && b[comma] != 44 { comma += 1 }
    if comma >= b.count { return nil }
    let header = draw.stringOf(b, 0, comma)
    var payload: [uint8] = []
    var i = comma + 1
    while i < b.count { payload.append(b[i]); i += 1 }
    if header.hasSuffix(";base64") {
        payload = base64Decode(payload)
    }
    return Decode(payload)
}

func base64Decode(_ input: [uint8]) -> [uint8] {
    var out: [uint8] = []
    var bits: uint32 = 0
    var count = 0
    for c in input {
        var v: int32 = -1
        if c >= 65 && c <= 90 { v = int32(c) - 65 }
        else if c >= 97 && c <= 122 { v = int32(c) - 97 + 26 }
        else if c >= 48 && c <= 57 { v = int32(c) - 48 + 52 }
        else if c == 43 || c == 45 { v = 62 }
        else if c == 47 || c == 95 { v = 63 }
        else { continue }
        bits = (bits << 6) | uint32(v)
        count += 6
        if count >= 8 {
            count -= 8
            out.append(uint8((bits >> uint32(count)) & 0xFF))
        }
    }
    return out
}
