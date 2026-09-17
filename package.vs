// The 'ui' package: a native window for Vertex.
import PackageDescription

let package = Package(
    name: "ui",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ui/window", targets: ["window"]),
        .executable(name: "hello", targets: ["hello"]),
        .executable(name: "paint", targets: ["paint"]),
        .executable(name: "lifecycle", targets: ["lifecycle"]),
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
    ]
)
