// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Nexus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Nexus", targets: ["Nexus"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "Nexus",
            dependencies: ["SwiftTerm"],
            path: "Sources/Nexus"
        ),
        .testTarget(
            name: "NexusTests",
            dependencies: ["Nexus"],
            path: "Tests/NexusTests"
        )
    ]
)
