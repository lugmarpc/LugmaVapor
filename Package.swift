// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LugmaVapor",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LugmaVapor",
            targets: ["LugmaVapor"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/rexmas/JSONValue.git", from: "7.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LugmaVapor",
            dependencies: [
            	.product(name: "Vapor", package: "vapor"),
                .product(name: "JSONValueRX", package: "JSONValue"),
            ]),
    ]
)
