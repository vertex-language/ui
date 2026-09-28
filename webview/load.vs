// Pages from the network: the page and what it refers to are fetched
// before the page is shown, and handed to it from memory. The report
// says what came back and what the engine couldn't use -- the list of
// what a site still needs.
package webview

import (
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
    /// The page's own <style> elements.
    var inlineStyles: [string] = []
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
    for style in doc.ElementsByTagName("style") {
        sheetsToScan.append((text: style.InnerText(), base: base))
        remote.inlineStyles.append(style.InnerText())
    }

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
                    // Fetched, but for WOFF2, which nothing here unpacks.
                    if !remote.fonts.contains(u) { remote.fonts.append(u) }
                    if isWoff2(u) { continue }
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

/// Whether a URL names a WOFF2 font, by its extension.
func isWoff2(_ u: string) -> bool {
    var path = u
    if let q = path.firstIndex(of: "?") { path = string(path[..<q]) }
    return path.lowercased().hasSuffix(".woff2")
}

/// Whether a URL names a font file, by its extension.
func isFont(_ u: string) -> bool {
    var path = u
    if let q = path.firstIndex(of: "?") { path = string(path[..<q]) }
    let lower = path.lowercased()
    return lower.hasSuffix(".woff2") || lower.hasSuffix(".woff") || lower.hasSuffix(".ttf") || lower.hasSuffix(".otf")
}

/// What a load brought back, and what the engine couldn't use: the list
/// of what a site still needs.
public struct LoadReport {
    /// Where the page ended up, after redirects.
    public var URL: string
    /// The page's HTTP status; 0 where it failed before one (Error says
    /// why), 200 for a file.
    public var Status: int32
    public var ContentType: string
    public var Error: string
    public var Bytes: int
    public var Resources: int
    public var Milliseconds: int
    public var Stylesheets: int
    public var StylesheetsLoaded: int
    public var Images: int
    public var ImagesDecoded: int
    /// Web fonts @font-face names; those fetched, and those left out as
    /// WOFF2, which isn't unpacked yet.
    public var Fonts: int
    public var FontsLoaded: int = 0
    public var FontsWoff2: int = 0
    /// "stylesheet URL: why" for each that failed.
    public var Failed: [string]
    /// "URL: content type" for each image nothing here decodes.
    public var Undecodable: [string]
    /// What the stylesheets declare, and what the engine applies.
    public var Coverage: css.Coverage

    /// The report as text, for a terminal.
    public func Text() -> string {
        var out = "\(URL): \(Status == 0 ? Error : "\(Status)") \(ContentType), \(Bytes / 1024) KB, \(Resources) resources in \(Milliseconds) ms\n"
        out += "  stylesheets: \(StylesheetsLoaded) of \(Stylesheets); images: \(ImagesDecoded) of \(Images) decoded\n"
        out += Coverage.Report()
        if Fonts > 0 {
            out += "  fonts: \(FontsLoaded) of \(Fonts) fetched"
            out += FontsWoff2 > 0 ? "; \(FontsWoff2) WOFF2, not unpacked yet (compress/brotli)\n" : "\n"
        }
        if !Failed.isEmpty { out += "failed:\n" + Failed.map { "  " + $0 }.joined(separator: "\n") + "\n" }
        if !Undecodable.isEmpty { out += "not decodable:\n" + Undecodable.map { "  " + $0 }.joined(separator: "\n") + "\n" }
        return out
    }
}

/// The report of a fetched page.
/// undecoded is the images the page couldn't decode (Page.LoadImages):
/// the report doesn't decode them again to find out.
func report(_ r: RemotePage, undecoded: [string] = []) -> LoadReport {
    var rep = LoadReport(URL: r.url, Status: r.page.status, ContentType: r.page.contentType, Error: r.page.error,
                         Bytes: r.page.body?.count ?? 0, Resources: r.resources.count, Milliseconds: int(r.elapsed * 1000),
                         Stylesheets: r.stylesheets.count, StylesheetsLoaded: 0, Images: r.images.count, ImagesDecoded: 0,
                         Fonts: r.fonts.count, Failed: [], Undecodable: [], Coverage: css.Coverage())
    for u in r.stylesheets {
        guard let l = r.resources[u] else { continue }
        if l.ok { rep.StylesheetsLoaded += 1 } else { rep.Failed.append("stylesheet \(u): \(l.status == 0 ? l.error : "\(l.status)")") }
    }
    for u in r.images {
        guard let l = r.resources[u] else { continue }
        if !l.ok {
            rep.Failed.append("image \(u): \(l.status == 0 ? l.error : "\(l.status)")")
        } else if undecoded.contains(u) {
            rep.Undecodable.append("\(u): \(l.contentType.isEmpty ? "unknown type" : l.contentType)")
        } else {
            rep.ImagesDecoded += 1
        }
    }
    for u in r.fonts {
        if isWoff2(u) { rep.FontsWoff2 += 1 } else if let l = r.resources[u], l.ok { rep.FontsLoaded += 1 }
    }
    for text in r.inlineStyles { rep.Coverage.Add(css.Parse(text)) }
    for u in r.stylesheets {
        if let l = r.resources[u], l.ok, let b = l.body { rep.Coverage.Add(css.Parse(string(decoding: b, as: UTF8.self))) }
    }
    return rep
}

/// A fetched page as an archive: the page and every resource, as they
/// came back.
func archive(_ r: RemotePage) -> fetch.Archive {
    var a = fetch.Archive(page: r.url)
    a.Add(fetch.ArchiveEntry(URL: r.url, Status: r.page.status, ContentType: r.page.contentType, Body: r.page.body ?? []))
    for (u, l) in r.resources {
        a.Add(fetch.ArchiveEntry(URL: u, Status: l.status, ContentType: l.contentType, Body: l.body ?? []))
    }
    return a
}
