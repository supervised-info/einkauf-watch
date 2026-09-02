// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EinkaufCore",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EinkaufCore", targets: ["EinkaufCore"])
    ],
    targets: [
        .target(
            name: "EinkaufCore",
            path: "Sources/Shared",
            exclude: [
                "ConnectivitySync.swift"
            ]
        ),
        .testTarget(
            name: "EinkaufCoreTests",
            dependencies: ["EinkaufCore"],
            path: "Tests/EinkaufCoreTests"
        )
    ]
)
