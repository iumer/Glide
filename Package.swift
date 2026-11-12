// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no event taps) so it can be self-tested.
        .target(name: "GlideCore", path: "Sources/GlideCore"),
        .executableTarget(
            name: "Glide",
            dependencies: ["GlideCore"],
            path: "Sources/Glide",
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(name: "GlideSelfTest", dependencies: ["GlideCore"], path: "Sources/GlideSelfTest"),
    ]
)
