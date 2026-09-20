// The 'ui' package: native windows and webviews for Vertex.
import PackageDescription

let package = Package(
    name: "ui",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ui/window", targets: ["window"]),
        .library(name: "ui/draw", targets: ["draw"]),
        .library(name: "ui/font", targets: ["font"]),
        .library(name: "ui/image", targets: ["image"]),
        .library(name: "ui/webview", targets: ["webview"]),
        .executable(name: "hello", targets: ["hello"]),
        .executable(name: "paint", targets: ["paint"]),
        .executable(name: "lifecycle", targets: ["lifecycle"]),
        .executable(name: "check-webview", targets: ["check-webview"]),
        .executable(name: "check-draw", targets: ["check-draw"]),
        .executable(name: "check-font", targets: ["check-font"]),
        .executable(name: "browser", targets: ["browser"]),
        .executable(name: "snapshot", targets: ["snapshot"]),
        .executable(name: "bench", targets: ["bench"]),
    ],
    targets: [
        // The platform's window system, as a C ABI.
        .target(
            name: "cwindow",
            path: "window/cwindow",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("QuartzCore"),
            ]
        ),
        // The package: Vertex types over cwindow.
        .target(
            name: "window",
            dependencies: ["cwindow"],
            path: "window",
            exclude: ["cwindow"]
        ),
        // Software drawing into RGBA pixels: fills, curves, masks, images.
        .target(
            name: "draw",
            path: "draw"
        ),
        // The platform's fonts, as a C ABI.
        .target(
            name: "cfont",
            path: "font/cfont",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("CoreText"),
            ]
        ),
        // Faces, shaping and glyph masks over cfont.
        .target(
            name: "font",
            dependencies: ["cfont", "draw"],
            path: "font",
            exclude: ["cfont"]
        ),
        // The platform's image decoders, as a C ABI.
        .target(
            name: "cimage",
            path: "image/cimage",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        // Image decoding over cimage.
        .target(
            name: "image",
            dependencies: ["cimage", "draw"],
            path: "image",
            exclude: ["cimage"]
        ),
        // The webview package: HTML/CSS layout & framebuffer rendering.
        .target(
            name: "webview",
            dependencies: ["window", "draw", "font", "image"],
            path: "webview"
        ),
        // A window that prints what happens to it.
        .executableTarget(
            name: "hello",
            dependencies: ["window"],
            path: "examples/hello"
        ),
        // Pixels, pointer input and frames.
        .executableTarget(
            name: "paint",
            dependencies: ["window"],
            path: "examples/paint"
        ),
        // The package checked against a real window.
        .executableTarget(
            name: "lifecycle",
            dependencies: ["window"],
            path: "tests/lifecycle"
        ),
        // Automated unit tests for HTML/CSS webview.
        .executableTarget(
            name: "check-webview",
            dependencies: ["window", "webview", "draw", "font", "image"],
            path: "tests/webview"
        ),
        // The rasterizer checked pixel by pixel.
        .executableTarget(
            name: "check-draw",
            dependencies: ["draw"],
            path: "tests/draw"
        ),
        // Fonts checked: metrics, shaping, masks.
        .executableTarget(
            name: "check-font",
            dependencies: ["font", "draw"],
            path: "tests/font"
        ),
        // An HTML file rendered to a PNG, with no window.
        .executableTarget(
            name: "snapshot",
            dependencies: ["window", "webview", "draw", "image"],
            path: "examples/snapshot"
        ),
        // The engine timed on a page.
        .executableTarget(
            name: "bench",
            dependencies: ["window", "webview", "draw", "image"],
            path: "examples/bench"
        ),
        // Full desktop HTML & CSS browser example.
        .executableTarget(
            name: "browser",
            dependencies: ["window", "webview", "draw", "font", "image"],
            path: "examples/browser"
        ),
    ]
)
