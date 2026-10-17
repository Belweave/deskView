// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DeskViewKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "DeskViewKit", targets: ["DeskViewKit"]),
               .executable(name: "DeskViewBench", targets: ["DeskViewBench"])],
    targets: [
        .target(name: "DeskViewKit"),
        .executableTarget(name: "DeskViewBench", dependencies: ["DeskViewKit"], path: "Tools/DeskViewBench"),
        .testTarget(name: "DeskViewKitTests", dependencies: ["DeskViewKit"])
    ],
    swiftLanguageModes: [.v6]
)
