// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "SPROUT",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SPROUT", targets: ["PDFUNK"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/SDWebImageWebPCoder.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "PDFUNK",
            dependencies: [.product(name: "SDWebImageWebPCoder", package: "SDWebImageWebPCoder")]
        )
    ],
    swiftLanguageVersions: [.v5]
)
