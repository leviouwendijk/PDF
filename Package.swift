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
        .executable(name: "t_pdf", targets: ["PDFTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Primitives.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/IO.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Readers.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "PDFCore",
            dependencies: [
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
                .product(name: "IO", package: "IO"),
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
        .executableTarget(
            name: "PDFTests",
            dependencies: [
                "PDF", "PDFCore", "PDFApple",
                .product(name: "Primitives", package: "Primitives"),
                .product(name: "Position", package: "Position"),
                .product(name: "IO", package: "IO"),
            ],
            path: "Testing/PDFTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
