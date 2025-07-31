// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tenex-ios",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/pablof7z/NDKSwift", revision: "9c9da851c57f28987f588084526751976c2b587a")
    ],
    targets: []
)