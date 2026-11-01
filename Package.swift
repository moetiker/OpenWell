// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenWell",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OpenWell", targets: ["OpenWell"]),
    ],
    targets: [
        // The free-spot search, free of AppKit and the accessibility API.
        .target(name: "OpenWellCore"),
        // The Dock app. `make app` puts it into OpenWell.app.
        .executableTarget(name: "OpenWell", dependencies: ["OpenWellCore"]),
        .testTarget(name: "OpenWellCoreTests", dependencies: ["OpenWellCore"]),
    ]
)
