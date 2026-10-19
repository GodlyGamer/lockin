// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CoreKit",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "CoreKit", targets: ["CoreKit"]),
    ],
    targets: [
        .target(name: "CoreKit"),
        .testTarget(name: "CoreKitTests", dependencies: ["CoreKit"]),
    ]
)
