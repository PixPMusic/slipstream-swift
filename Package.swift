// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SlipstreamCore", platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SlipstreamCore", targets: ["SlipstreamCore"])],
    targets: [
        .target(name: "SlipstreamCore", path: "Slipstream/Core"),
        .testTarget(name: "SlipstreamCoreTests", dependencies: ["SlipstreamCore"], path: "Tests")
    ]
)
