package draw

/// Encodes an image as a PNG: 8-bit RGBA, stored uncompressed in the
/// zlib stream, which every reader takes. For screenshots and tests;
/// a file this makes is large, not slow.
public func EncodePNG(_ image: Image) -> [uint8] {
    var out: [uint8] = [137, 80, 78, 71, 13, 10, 26, 10]
    var header: [uint8] = []
    appendU32(&header, uint32(image.Width))
    appendU32(&header, uint32(image.Height))
    header.append(8)  // bit depth
    header.append(6)  // color type: RGBA
    header.append(0)
    header.append(0)
    header.append(0)
    chunk(&out, "IHDR", header)

    // Rows with a filter byte, unpremultiplied.
    var raw: [uint8] = []
    let w = int(image.Width)
    var y = 0
    while y < int(image.Height) {
        raw.append(0)
        var x = 0
        while x < w {
            let i = (y * w + x) * 4
            let a = uint32(image.Pixels[i + 3])
            if a == 0 || a == 255 {
                raw.append(image.Pixels[i])
                raw.append(image.Pixels[i + 1])
                raw.append(image.Pixels[i + 2])
            } else {
                raw.append(uint8((uint32(image.Pixels[i]) * 255 + a / 2) / a))
                raw.append(uint8((uint32(image.Pixels[i + 1]) * 255 + a / 2) / a))
                raw.append(uint8((uint32(image.Pixels[i + 2]) * 255 + a / 2) / a))
            }
            raw.append(uint8(a))
            x += 1
        }
        y += 1
    }
    var z: [uint8] = [0x78, 0x01]
    var pos = 0
    while pos < raw.count || pos == 0 {
        var n = raw.count - pos
        if n > 65535 { n = 65535 }
        let last = pos + n >= raw.count
        z.append(last ? 1 : 0)
        z.append(uint8(n & 0xFF))
        z.append(uint8((n >> 8) & 0xFF))
        z.append(uint8(~n & 0xFF))
        z.append(uint8((~n >> 8) & 0xFF))
        var i = 0
        while i < n {
            z.append(raw[pos + i])
            i += 1
        }
        pos += n
        if raw.isEmpty { break }
    }
    appendU32(&z, adler32(raw))
    chunk(&out, "IDAT", z)
    chunk(&out, "IEND", [])
    return out
}

func appendU32(_ out: inout [uint8], _ v: uint32) {
    out.append(uint8(v >> 24))
    out.append(uint8((v >> 16) & 0xFF))
    out.append(uint8((v >> 8) & 0xFF))
    out.append(uint8(v & 0xFF))
}

func chunk(_ out: inout [uint8], _ type: string, _ data: [uint8]) {
    appendU32(&out, uint32(data.count))
    var body: [uint8] = []
    for b in type.utf8 { body.append(b) }
    for b in data { body.append(b) }
    for b in body { out.append(b) }
    appendU32(&out, crc32(body))
}

var crcTable: [uint32] = []

func crc32(_ data: [uint8]) -> uint32 {
    if crcTable.isEmpty {
        var n: uint32 = 0
        while n < 256 {
            var c = n
            var k = 0
            while k < 8 {
                if c & 1 != 0 { c = 0xEDB88320 ^ (c >> 1) } else { c = c >> 1 }
                k += 1
            }
            crcTable.append(c)
            n += 1
        }
    }
    var c: uint32 = 0xFFFFFFFF
    for b in data {
        c = crcTable[int((c ^ uint32(b)) & 0xFF)] ^ (c >> 8)
    }
    return c ^ 0xFFFFFFFF
}

func adler32(_ data: [uint8]) -> uint32 {
    var a: uint32 = 1
    var b: uint32 = 0
    for byte in data {
        a = (a + uint32(byte)) % 65521
        b = (b + a) % 65521
    }
    return (b << 16) | a
}
