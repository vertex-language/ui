// Pages from the network: the page and what it refers to are fetched
// before the page is shown, and handed to it from memory. The report
// says what came back and what the engine couldn't use -- the list of
// what a site still needs.
package main

import (
    "image/format"
    "net/http"
    "time"
    "web/css"
    "web/fetch"
    "web/html"
)

/// One resource as the network answered it.
struct Loaded {
    var url: string
    var status: int32
    var contentType: string
    var body: [uint8]?
    var error: string

    var ok: bool { return body != nil && status >= 200 && status < 300 }
}

/// A page and everything fetched for it, by resolved URL.
struct RemotePage {
    var url: string
    var page: Loaded
    var resources: [string: Loaded] = [:]
    var stylesheets: [string] = []
    var images: [string] = []
    var fonts: [string] = []
    var elapsed: float64 = 0
}

/// Gets a URL, following up to five redirects.
func get(_ url: string) async -> Loaded {
    var current = url
    var hops = 0
    while true {
        do {
            let res = try await http.Get(current)
            if res.StatusCode >= 300 && res.StatusCode < 400, let loc = res.Headers.Get("Location"), hops < 5 {
                current = fetch.Resolve(loc, against: current)
                hops += 1
                continue
            }
            return Loaded(url: current, status: res.StatusCode, contentType: res.Headers.Get("Content-Type") ?? "", body: res.Body, error: "")
        } catch {
            return Loaded(url: current, status: 0, contentType: "", body: nil, error: "\(error)")
        }
    }
}

/// Gets many URLs at once, each once.
func getAll(_ urls: [string]) async -> [string: Loaded] {
    var out: [string: Loaded] = [:]
    await withTaskGroup(of: Loaded.self) { group in
        var seen = Set<string>()
        for u in urls where !seen.contains(u) {
            seen.insert(u)
            group.addTask { await get(u) }
        }
        for await l in group {
            out[l.url] = l
        }
    }
    return out
}

/// Fetches a page and the stylesheets and images it names: the page's
/// <link rel=stylesheet> and <img src>, then what those stylesheets
/// @import and url() in turn.
func fetchPage(_ url: string) async -> RemotePage {
    let start = time.Instant.Now()
    let page = await get(url)
    var remote = RemotePage(url: page.url, page: page)
    guard page.ok, let body = page.body else { return remote }
    let doc = html.Parse(string(decoding: body, as: UTF8.self))
    var base = page.url
    if let b = doc.ElementsByTagName("base").first, let href = b.GetAttribute("href"), !href.isEmpty {
        base = fetch.Resolve(href, against: page.url)
    }

    var wanted: [string] = []
    for link in doc.ElementsByTagName("link") {
        let rel = (link.GetAttribute("rel") ?? "").lowercased()
        if rel.contains("stylesheet"), let href = link.GetAttribute("href"), !href.isEmpty {
            let u = fetch.Resolve(href, against: base)
            remote.stylesheets.append(u)
            wanted.append(u)
        }
    }
    for img in doc.ElementsByTagName("img") {
        if let src = img.GetAttribute("src"), !src.isEmpty, !src.hasPrefix("data:") {
            let u = fetch.Resolve(src, against: base)
            remote.images.append(u)
            wanted.append(u)
        }
    }
    // What the page's own <style> elements refer to.
    var sheetsToScan: [(text: string, base: string)] = []
    for style in doc.ElementsByTagName("style") { sheetsToScan.append((text: style.InnerText(), base: base)) }

    var round = 0
    while round < 3 {
        let got = await getAll(wanted.filter { remote.resources[$0] == nil })
        for (u, l) in got { remote.resources[u] = l }
        // Stylesheets fetched this round, scanned for more.
        for u in wanted where remote.stylesheets.contains(u) {
            if let l = remote.resources[u], l.ok, let b = l.body {
                sheetsToScan.append((text: string(decoding: b, as: UTF8.self), base: l.url))
            }
        }
        wanted = []
        for sheet in sheetsToScan {
            for ref in cssReferences(sheet.text) {
                let u = fetch.Resolve(ref.url, against: sheet.base)
                if remote.resources[u] != nil { continue }
                if ref.isImport {
                    if !remote.stylesheets.contains(u) { remote.stylesheets.append(u) }
                } else if isFont(u) {
                    if !remote.fonts.contains(u) { remote.fonts.append(u) }
                    continue
                } else if !u.hasPrefix("data:") {
                    if !remote.images.contains(u) { remote.images.append(u) }
                } else {
                    continue
                }
                wanted.append(u)
            }
        }
        sheetsToScan = []
        if wanted.isEmpty { break }
        round += 1
    }
    remote.elapsed = start.Elapsed().AsSeconds()
    return remote
}

/// The URLs a stylesheet names: @import targets and url() values.
func cssReferences(_ text: string) -> [(url: string, isImport: bool)] {
    var out: [(url: string, isImport: bool)] = []
    let sheet = css.Parse(text)
    for at in sheet.AtRules where at.Name == "import" {
        let u = importTarget(at.Params)
        if !u.isEmpty { out.append((url: u, isImport: true)) }
    }
    // url() anywhere: declarations, @font-face and @media blocks alike.
    let b = [uint8](text.utf8)
    var i = 0
    while i + 4 < b.count {
        if (b[i] == 117 || b[i] == 85) && (b[i + 1] == 114 || b[i + 1] == 82) && (b[i + 2] == 108 || b[i + 2] == 76) && b[i + 3] == 40 {
            var j = i + 4
            while j < b.count && (b[j] == 32 || b[j] == 34 || b[j] == 39) { j += 1 }
            let start = j
            while j < b.count && b[j] != 41 && b[j] != 34 && b[j] != 39 { j += 1 }
            let u = string(decoding: b[start..<j], as: UTF8.self)
            if !u.isEmpty && !u.hasPrefix("#") { out.append((url: u, isImport: false)) }
            i = j
        }
        i += 1
    }
    return out
}

func importTarget(_ params: string) -> string {
    let b = [uint8](params.utf8)
    var i = 0
    while i < b.count && b[i] == 32 { i += 1 }
    if i + 4 < b.count && b[i] == 117 && b[i + 3] == 40 { i += 4 }
    while i < b.count && (b[i] == 32 || b[i] == 34 || b[i] == 39) { i += 1 }
    let start = i
    while i < b.count && b[i] != 34 && b[i] != 39 && b[i] != 41 && b[i] != 32 { i += 1 }
    return string(decoding: b[start..<i], as: UTF8.self)
}

/// Whether a URL names a font file, by its extension.
func isFont(_ u: string) -> bool {
    var path = u
    if let q = path.firstIndex(of: "?") { path = string(path[..<q]) }
    let lower = path.lowercased()
    return lower.hasSuffix(".woff2") || lower.hasSuffix(".woff") || lower.hasSuffix(".ttf") || lower.hasSuffix(".otf")
}

/// What came back, and what the engine couldn't use.
func report(_ r: RemotePage) -> string {
    var out = "\(r.url): \(r.page.status == 0 ? r.page.error : "\(r.page.status)") \(r.page.contentType), \((r.page.body?.count ?? 0) / 1024) KB, \(r.resources.count) resources in \(int(r.elapsed * 1000)) ms\n"
    var failed: [string] = []
    var undecodable: [string] = []
    var sheetsOK = 0
    var imagesOK = 0
    for u in r.stylesheets {
        guard let l = r.resources[u] else { continue }
        if l.ok { sheetsOK += 1 } else { failed.append("  stylesheet \(u): \(l.status == 0 ? l.error : "\(l.status)")") }
    }
    for u in r.images {
        guard let l = r.resources[u] else { continue }
        if !l.ok {
            failed.append("  image \(u): \(l.status == 0 ? l.error : "\(l.status)")")
        } else if let b = l.body, format.Decode(b) == nil {
            undecodable.append("  image \(u): \(l.contentType.isEmpty ? "unknown type" : l.contentType)")
        } else {
            imagesOK += 1
        }
    }
    out += "  stylesheets: \(sheetsOK) of \(r.stylesheets.count); images: \(imagesOK) of \(r.images.count) decoded\n"
    if !r.fonts.isEmpty {
        out += "  fonts: \(r.fonts.count) named by @font-face, not fetched: the page registers fonts from local files only\n"
    }
    if !failed.isEmpty { out += "failed:\n" + failed.joined(separator: "\n") + "\n" }
    if !undecodable.isEmpty { out += "not decodable:\n" + undecodable.joined(separator: "\n") + "\n" }
    return out
}
