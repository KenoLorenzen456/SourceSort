// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SourceSort",
    platforms: [.macOS(.v15)],
    targets: [
        // UI-independent logic: source detection, rules, file operations. Unit-tested.
        .target(name: "SourceSortCore"),
        // The menu-bar app. Packaged into SourceSort.app by Scripts/build-app.sh.
        .executableTarget(name: "SourceSort", dependencies: ["SourceSortCore"]),
        // Debug CLI: prints what SourceSort detects for a file.
        .executableTarget(name: "sourcesort-probe", dependencies: ["SourceSortCore"]),
        .testTarget(name: "SourceSortCoreTests", dependencies: ["SourceSortCore"]),
    ],
    swiftLanguageModes: [.v5]
)
