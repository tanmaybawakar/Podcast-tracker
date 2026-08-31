// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PodcastTracker",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(
            url: "https://github.com/arraypress/swift-youtube-metadata.git",
            revision: "ba3ed87b7d8ce99a1b510f12ba453547c4a4d3cc"
        ),
        .package(
            url: "https://github.com/b5i/YouTubeKit.git",
            revision: "6532af39da4c1612b0a1af603792419d8fb0e67f"
        )
    ],
    targets: [
        .executableTarget(
            name: "PodcastTracker",
            dependencies: [
                .product(name: "YouTubeTranscript", package: "swift-youtube-metadata"),
                .product(name: "YouTubeKit", package: "YouTubeKit")
            ],
            path: "Sources/PodcastTracker",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PodcastTrackerTests",
            dependencies: ["PodcastTracker"],
            path: "Tests/PodcastTrackerTests"
        )
    ]
)
