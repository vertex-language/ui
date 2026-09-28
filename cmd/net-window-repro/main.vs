// Fetches a page's resources at once while a window is up: the executor
// is then AppKit's guest, and its descriptor waits go through idleWait.
package main

import (
    "net/http"
    "time"
    "ui/window"
)

let start = time.Instant.Now()

func ms() -> int { return int(start.Elapsed().AsSeconds() * 1000) }

let urls: [string] = [
    "https://about.google/",
    "https://fonts.googleapis.com/css2?family=Product+Sans&family=Google+Sans+Display:ital,wght@0,400;0,500;0,700;1,400;1,500;1,700&family=Google+Sans:ital,wght@0,400;0,500;0,700;1,400;1,500;1,700&family=Google+Sans+Text:ital,wght@0,400;0,500;0,700;1,400;1,500;1,700&display=swap",
    "https://www.gstatic.com/glue/cookienotificationbar/cookienotificationbar.min.css",
    "https://www.gstatic.com/marketing-cms/assets/images/1e/23/1ba122344711850cd122975e8129/about-homepage-3up-research.png=n-w543-h305-fcrop64=1,00000051ffffffff-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/44/fc/c54214824bbf9c98f4d5eaef3eb1/event-made-on-logo-graphic-black.webp=n-w543-h305-fcrop64=1,0000004effffffff-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/5b/b0/3a62c7b4486e943fceeeb3fe90df/g-about-gatg.png=n-w64-h65-fcrop64=1,000005f5ffffffff-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/80/0d/4ee8c3384f819609e7dcdf777e83/about-homepage-3up-exploreproducts-1.webp=n-w543-h361-fcrop64=1,0000140effffebaf-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/9d/f8/6ff52e274df88a0dcb150746f9f9/about-3up-gdm.webp=n-w543-h305-fcrop64=1,0000003dffffffc3-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/b3/a5/529a3d3047d18be9a5f3547ad7e3/google-logo-footer.svg",
    "https://www.gstatic.com/marketing-cms/assets/images/ee/11/085bb1454d70aea1d954cf3f7eca/tts-thumbnail-1-1.webp=n-w531-h299-fcrop64=1,00230000ffddffff-rw",
    "https://www.gstatic.com/marketing-cms/assets/images/f5/d3/a7f9db7045429cb6dc6be56bdcbe/google-logo-about.svg"
]

func one(_ i: int) async -> string {
    do {
        let res = try await http.Get(urls[i])
        return "\(i): \(res.StatusCode) \(res.Body.count) bytes at \(ms()) ms"
    } catch {
        return "\(i): error \(error)"
    }
}

@MainActor
func fetchAll() async -> int {
    var failed = 0
    await withTaskGroup(of: string.self) { group in
        for i in 0..<urls.count {
            group.addTask { await one(i) }
        }
        for await line in group {
            if line.contains("error") { failed += 1 }
            print(line)
        }
    }
    return failed
}

@MainActor
func main() async -> int32 {
    let w: window.Window
    do {
        w = try window.Create(title: "Net repro", size: window.Size(320, 200))
    } catch {
        return 1
    }
    var result: int32 = -1
    Task {
        let failed = await fetchAll()
        print("failed: \(failed) of \(urls.count)")
        result = int32(failed)
        w.RequestFrame()
    }
    while let _ = await w.WaitEvent() {
        if result >= 0 { break }
    }
    w.Close()
    return result
}
