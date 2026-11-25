// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PDF",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "PDF", targets: ["PDF"]),
        .library(name: "PDFCore", targets: ["PDFCore"]),
        .library(name: "PDFApple", targets: ["PDFApple"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-lco/Primitives.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Position.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/IO.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Readers.git", branch: "master"),
        .package(url: "https://github.com/swift-lco/Schema.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "PDFCore",
            dependencies: [
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
                .product(name: "IO", package: "IO"),
                .product(name: "Schema", package: "Schema"),
            ]
        ),
        .target(
            name: "PDFApple",
            dependencies: [
                "PDFCore",
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
                .product(name: "IO", package: "IO"),
                .product(name: "Readers", package: "Readers"),
            ]
        ),
        .target(
            name: "PDF",
            dependencies: ["PDFCore", "PDFApple"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        settings.append(
            .unsafeFlags(
                [
                    "-continue-building-after-errors"
                ]
            )
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
