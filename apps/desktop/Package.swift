// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlexusOneDesktop",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PlexusOneDesktop", targets: ["PlexusOneDesktop"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "b6ce28a4b222b06d76a3fd44e904e00a95044d53"),
        .package(url: "https://github.com/plexusone/assistantkit-swift.git", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "PlexusOneDesktop",
            dependencies: [
                "SwiftTerm",
                .product(name: "AssistantKit", package: "assistantkit-swift")
            ],
            path: "Sources/PlexusOneDesktop",
            exclude: [
                "Info.plist",
                "PlexusOneDesktop.entitlements"
            ],
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "PlexusOneDesktopTests",
            dependencies: ["PlexusOneDesktop"],
            path: "Tests/PlexusOneDesktopTests"
        )
    ]
)
