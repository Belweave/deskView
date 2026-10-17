// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "DeskViewKit",
    platforms: [.macOS(.v26)],
    products: [.library(name: "DeskViewKit", targets: ["DeskViewKit"])],
    targets: [
        .target(name: "DeskViewKit"),
        .testTarget(name: "DeskViewKitTests", dependencies: ["DeskViewKit"])
    ],
    swiftLanguageModes: [.v6]
)
