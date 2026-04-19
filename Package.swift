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
            targets: ["FlopperKitKmp", "FlopperAppleShim"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: "FlopperKitKmp",
            path: "flopper-ios/build/XCFrameworks/release/FlopperKitKmp.xcframework"
        ),
        .binaryTarget(
            name: "FlopperAppleShim",
            path: "flopper-ios/build/XCFrameworks/release/FlopperAppleShim.xcframework"
        ),
    ]
)
