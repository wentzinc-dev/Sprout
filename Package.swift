// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "PDFUNK",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PDFUNK", targets: ["PDFUNK"])
    ],
    targets: [
        .executableTarget(name: "PDFUNK")
    ],
    swiftLanguageVersions: [.v5]
)
