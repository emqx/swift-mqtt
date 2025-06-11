// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-mqtt",
    platforms: [.iOS(.v13),.watchOS(.v6),.macOS(.v10_15),.tvOS(.v13)],
    products: [
        .library(
            name: "MQTT",
            targets: ["MQTT"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sutext/swift-promise", from: "2.2.0"),
    ],
    targets: [
        .target(
            name: "MQTT",
            dependencies: [
                .product(name: "Promise", package: "swift-promise")
            ]
        ),
        .testTarget(
            name: "MQTTTests",
            dependencies: ["MQTT"]),
    ]
)
