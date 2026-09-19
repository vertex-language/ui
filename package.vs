// The 'ui' package: native windows and webviews for Vertex.
import PackageDescription

let package = Package(
    name: "ui",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ui/window", targets: ["window"]),
        .library(name: "ui/webview", targets: ["webview"]),
        .executable(name: "hello", targets: ["hello"]),
        .executable(name: "paint", targets: ["paint"]),
        .executable(name: "lifecycle", targets: ["lifecycle"]),
        .executable(name: "check-webview", targets: ["check-webview"]),
        .executable(name: "browser", targets: ["browser"]),
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
        // The webview package: HTML/CSS layout & framebuffer rendering.
        .target(
            name: "webview",
            dependencies: ["window", "cwindow"],
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
            dependencies: ["window", "webview"],
            path: "tests/webview"
        ),
        // Full desktop HTML & CSS browser example.
        .executableTarget(
            name: "browser",
            dependencies: ["window", "webview"],
            path: "examples/browser"
        ),
    ]
)
