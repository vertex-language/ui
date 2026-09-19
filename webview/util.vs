package webview

func bytesFromString(_ text: string) -> [uint8] {
    var out: [uint8] = []
    for b in text.utf8 {
        out.append(b)
    }
    return out
}

func stringFromBytes(_ bytes: [uint8], from start: int, to end: int) -> string {
    if start >= end { return "" }
    var chars: [CChar] = []
    var i = start
    while i < end {
        chars.append(CChar(truncatingIfNeeded: bytes[i]))
        i += 1
    }
    chars.append(0)
    return string(cString: chars)
}

func toLower(_ s: string) -> string {
    var b: [uint8] = []
    for byte in s.utf8 {
        if byte >= 65 && byte <= 90 {
            b.append(byte + 32)
        } else {
            b.append(byte)
        }
    }
    return stringFromBytes(b, from: 0, to: b.count)
}

func isWhitespace(_ b: uint8) -> bool {
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 12
}

func trimString(_ s: string) -> string {
    let bytes = bytesFromString(s)
    if bytes.isEmpty { return "" }
    var start = 0
    while start < bytes.count && isWhitespace(bytes[start]) {
        start += 1
    }
    var end = bytes.count
    while end > start && isWhitespace(bytes[end - 1]) {
        end -= 1
    }
    return stringFromBytes(bytes, from: start, to: end)
}

func collapseWhitespace(_ s: string, preserveLeading: bool) -> string {
    let bytes = bytesFromString(s)
    if bytes.isEmpty { return "" }
    var result: [uint8] = []
    var inSpace = !preserveLeading

    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if isWhitespace(b) {
            if !inSpace {
                result.append(32)
                inSpace = true
            }
        } else {
            result.append(b)
            inSpace = false
        }
        i += 1
    }
    return stringFromBytes(result, from: 0, to: result.count)
}

func parseFloat(_ s: string) -> float32 {
    let bytes = bytesFromString(s)
    var integerPart: float32 = 0.0
    var fracPart: float32 = 0.0
    var fracDiv: float32 = 10.0
    var seenDot = false

    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if b == 46 { // '.'
            seenDot = true
        } else if b >= 48 && b <= 57 {
            let digit = float32(b - 48)
            if seenDot {
                fracPart += digit / fracDiv
                fracDiv *= 10.0
            } else {
                integerPart = integerPart * 10.0 + digit
            }
        } else if b != 32 { // non-digit, stop (e.g. "px", "em")
            break
        }
        i += 1
    }
    return integerPart + fracPart
}

func insertString(_ original: string, at index: int, _ insertion: string) -> string {
    let ob = bytesFromString(original)
    let ib = bytesFromString(insertion)
    let idx = index < 0 ? 0 : (index > ob.count ? ob.count : index)
    var result: [uint8] = []
    var i = 0
    while i < idx {
        result.append(ob[i])
        i += 1
    }
    var j = 0
    while j < ib.count {
        result.append(ib[j])
        j += 1
    }
    while i < ob.count {
        result.append(ob[i])
        i += 1
    }
    return stringFromBytes(result, from: 0, to: result.count)
}

func deleteCharBefore(_ original: string, at index: int) -> (result: string, newIndex: int) {
    let ob = bytesFromString(original)
    if index <= 0 || ob.isEmpty { return (result: original, newIndex: 0) }
    let idx = index > ob.count ? ob.count : index
    var result: [uint8] = []
    var i = 0
    while i < idx - 1 {
        result.append(ob[i])
        i += 1
    }
    i = idx
    while i < ob.count {
        result.append(ob[i])
        i += 1
    }
    return (result: stringFromBytes(result, from: 0, to: result.count), newIndex: idx - 1)
}

func substringUpTo(_ s: string, _ count: int) -> string {
    let b = bytesFromString(s)
    let n = count > b.count ? b.count : (count < 0 ? 0 : count)
    return stringFromBytes(b, from: 0, to: n)
}

func getNodeValue(_ node: html.Node) -> string {
    if let v = node.GetAttribute("value") {
        return v
    }
    if toLower(node.TagName) == "textarea" {
        return node.InnerText()
    }
    return ""
}

func getNodeName(_ node: html.Node, defaultName: string) -> string {
    if let name = node.GetAttribute("name") {
        return name
    }
    if let id = node.GetAttribute("id") {
        return id
    }
    return defaultName
}

func getNodePlaceholder(_ node: html.Node) -> string {
    if let p = node.GetAttribute("placeholder") {
        return p
    }
    return ""
}

