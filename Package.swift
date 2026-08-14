// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Logbook",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Logbook", targets: ["Logbook"])
    ],
    targets: [
        .target(name: "Logbook"),
        .testTarget(name: "LogbookTests", dependencies: ["Logbook"])
    ]
)
