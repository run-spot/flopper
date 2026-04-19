// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlopperKitKmp",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(
            name: "FlopperKitKmp",
            targets: ["FlopperKitKmp"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "FlopperKitKmp",
            path: "flopper-ios/build/XCFrameworks/release/FlopperKitKmp.xcframework"
        ),
    ]
)
