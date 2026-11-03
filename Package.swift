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

        // testing
        .executable(name: "t_pdf", targets: ["PDFTests"]),
        .executable(name: "t_pdf_fixtures", targets: ["PDFFixtureTests"]),
    ],
    dependencies: [
        .package(url: "https://github.com/leviouwendijk/Primitives.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Position.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/IO.git", branch: "master"),
        .package(url: "https://github.com/leviouwendijk/Readers.git", branch: "master"),

        // for test fixtures
        .package(url: "https://github.com/leviouwendijk/Milieu.git", branch: "master"),
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
        .executableTarget(
            name: "PDFFixtureTests",
            dependencies: [
                "PDF", "PDFCore", "PDFApple",
                .product(name: "Milieu", package: "Milieu"),
            ],
            path: "Testing/PDFFixtureTests"
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
