package webview

import (
    "web/css"
    "web/fetch"
)

// Navigation: what the view shows, where it has been, and getting there.
// A file is shown at once; a page from the network is fetched with what
// it refers to (load.vs), and shown once it is all in.

extension WebView {
    /// The address the view shows, after redirects: a URL or a path.
    public var URL: string { return url }

    /// Whether a page is on its way from the network.
    public var IsLoading: bool { return loading }

    public var CanGoBack: bool { return position > 0 }
    public var CanGoForward: bool { return position + 1 < history.count }

    /// Called as a load starts, with its address.
    public func OnLoadStarted(_ handler: (string) -> Void) { onLoadStarted = handler }

    /// Called once a page is shown, or has failed, with what came back:
    /// the host redraws, and may print the report.
    public func OnLoadFinished(_ handler: (LoadReport) -> Void) { onLoadFinished = handler }

    /// Shows an address, adding it to the history: http(s) URLs from the
    /// network, file: URLs and paths from disk, and "about:home" (or "")
    /// the start page.
    public func Navigate(_ address: string) {
        go(address, record: true)
    }

    public func Back() {
        if !CanGoBack { return }
        position -= 1
        go(history[position], record: false)
    }

    public func Forward() {
        if !CanGoForward { return }
        position += 1
        go(history[position], record: false)
    }

    /// Shows the current address again, from the network or disk.
    public func Reload() {
        if !url.isEmpty { go(url, record: false) }
    }

    /// Marks an address visited, for :visited.
    public func MarkVisited(_ address: string) {
        if !visited.contains(address) {
            visited.insert(address)
            Page.VisitedChanged()
        }
    }

    func go(_ address: string, record: bool) {
        var target = address
        if target.isEmpty || target == "about:home" { target = StartPage }
        url = target
        MarkVisited(target)
        loads += 1
        if record {
            while history.count > position + 1 { history.removeLast() }
            history.append(target)
            position = history.count - 1
        }
        if let h = onLoadStarted { h(target) }
        let scheme = fetch.Scheme(target)
        if scheme == "http" || scheme == "https" {
            loading = true
            let generation = loads
            Task { await self.loadRemote(target, generation) }
            return
        }
        loading = false
        Page.Configuration.Fetcher = fetch.Fetcher()
        var rep = fileReport(target)
        if scheme == "" || scheme == "file" {
            let path = fetch.FilePath(target)
            do {
                try Page.LoadFile(path)
            } catch {
                rep.Status = 0
                rep.Error = "cannot read the file"
                showMessage("Can't open the file", path)
            }
        } else {
            rep.Status = 0
            rep.Error = "no way to open a \(scheme): address"
            showMessage("Can't open this", "There's no way to open <code>\(target)</code> here.")
        }
        if let h = onLoadFinished { h(rep) }
    }

    /// Fetches a page and what it refers to, then shows it: unless the
    /// view went elsewhere meanwhile.
    func loadRemote(_ target: string, _ generation: int) async {
        let remote = await fetchPage(target)
        if generation != loads { return }
        loading = false
        let rep = report(remote)
        if let dir = RecordInto {
            try? archive(remote).Write(to: dir)
        }
        if remote.page.ok, let body = remote.page.body {
            url = remote.url
            if position >= 0 && position < history.count { history[position] = remote.url }
            MarkVisited(remote.url)
            let resources = remote.resources
            Page.Configuration.Fetcher = fetch.Fetcher({ u in
                if let l = resources[u], l.ok { return l.body }
                return nil
            })
            Page.LoadBytes(body, contentType: remote.page.contentType, baseURL: remote.url)
        } else {
            let why = remote.page.status == 0 ? remote.page.error : "the server answered \(remote.page.status)"
            showMessage("Can't load the page", "<code>\(target)</code>: \(why)")
        }
        if let h = onLoadFinished { h(rep) }
    }

    func showMessage(_ heading: string, _ text: string) {
        Page.LoadHTML("<body style='font-family:system-ui;margin:40px;color:#333'><h2 style='margin-top:0'>\(heading)</h2><p>\(text)</p><p><a href='about:home'>Start page</a></p></body>")
    }
}

/// The report of a page from disk: nothing fetched, nothing to list.
func fileReport(_ address: string) -> LoadReport {
    return LoadReport(URL: address, Status: 200, ContentType: "text/html", Error: "", Bytes: 0, Resources: 0, Milliseconds: 0,
                      Stylesheets: 0, StylesheetsLoaded: 0, Images: 0, ImagesDecoded: 0, Fonts: 0, Failed: [], Undecodable: [],
                      Coverage: css.Coverage())
}
