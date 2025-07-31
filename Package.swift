// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tenex-ios",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(url: "https://github.com/pablof7z/NDKSwift", branch: "master")
    ],
    targets: []
)